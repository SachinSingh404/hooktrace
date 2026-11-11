# frozen_string_literal: true

require "json"
require "securerandom"

module Hooktrace
  class InvalidPayloadError < StandardError; end

  class WebhookOutcome
    attr_reader :result, :provider, :event_id, :event_type, :matched_contracts

    def initialize(result:, provider:, event_id:, event_type:, matched_contracts:)
      @result = result
      @provider = provider
      @event_id = event_id
      @event_type = event_type
      @matched_contracts = matched_contracts.freeze
      freeze
    end

    def valid?
      result.valid?
    end

    def invalid?
      result.invalid?
    end

    def errors
      result.errors
    end

    def to_h
      {
        status: valid? ? "success" : "contract_violation",
        provider: provider,
        event_id: event_id,
        event_type: event_type,
        valid: valid?,
        matched_contracts: matched_contracts,
        errors: errors.map(&:to_h)
      }
    end
  end

  class WebhookProcessor
    def self.process(payload_or_raw, headers: {}, provider: nil, event_type: nil, id: nil,
                     strict: false, record: Hooktrace.auto_record)
      new.process(
        payload_or_raw,
        headers: headers,
        provider: provider,
        event_type: event_type,
        id: id,
        strict: strict,
        record: record
      )
    end

    def process(payload_or_raw, headers: {}, provider: nil, event_type: nil, id: nil,
                strict: false, record: Hooktrace.auto_record)
      payload = parse_payload(payload_or_raw)
      norm_headers = normalize_headers(headers)

      resolved_provider = (provider || detect_provider(payload, norm_headers)).to_s
      resolved_type = (event_type || extract_event_type(payload, norm_headers, resolved_provider)).to_s
      resolved_id = (id || extract_event_id(payload, norm_headers)).to_s

      contracts = match_contracts(resolved_provider, resolved_type)
      result = validate_or_record_unmatched(
        contracts, payload,
        provider: resolved_provider, event_type: resolved_type, id: resolved_id,
        strict: strict, record: record
      )

      WebhookOutcome.new(
        result: result,
        provider: resolved_provider,
        event_id: resolved_id,
        event_type: resolved_type,
        matched_contracts: contracts
      )
    end

    private

    def parse_payload(payload_or_raw)
      parsed = payload_or_raw.is_a?(String) ? JSON.parse(payload_or_raw) : payload_or_raw
      raise InvalidPayloadError, "Webhook payload must be a JSON object (Hash)" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise InvalidPayloadError, "Invalid JSON payload: #{e.message}"
    end

    def normalize_headers(headers)
      return {} unless headers.respond_to?(:each)

      headers.each_with_object({}) do |(key, val), acc|
        next unless key.is_a?(String) || key.is_a?(Symbol)

        normalized = key.to_s.downcase.sub(/\Ahttp_/, "").tr("_", "-")
        acc[normalized] = val
      end
    end

    def detect_provider(payload, headers)
      if headers.key?("stripe-signature") || payload["object"] == "event"
        "stripe"
      elsif headers.key?("paypal-auth-algo") || (payload["resource_type"] && payload["event_type"])
        "paypal"
      else
        "unknown"
      end
    end

    def extract_event_type(payload, _headers, provider)
      case provider
      when "stripe" then payload["type"] || "unknown"
      when "paypal" then payload["event_type"] || "unknown"
      else payload["event_type"] || payload["type"] || "unknown"
      end
    end

    def extract_event_id(payload, headers)
      payload["id"] || headers["paypal-transmission-id"] || SecureRandom.hex(8)
    end

    def match_contracts(provider, event_type)
      ensure_provider_loaded(provider)

      matched = []
      base = "#{provider}.event.base"
      matched << base if Hooktrace.registry.key?(base)

      if event_type && !event_type.empty? && event_type != "unknown"
        specific = find_matching_contract(provider, event_type)
        matched << specific if specific
      end

      matched.uniq
    end

    def ensure_provider_loaded(provider)
      return if Hooktrace.registry.keys.any? { |k| k.start_with?("#{provider}.") }

      Hooktrace.load_builtin_contracts!(provider) if Hooktrace.builtin_providers.include?(provider)
    end

    def find_matching_contract(provider, event_type)
      ["#{provider}.#{event_type}", event_type].find { |name| Hooktrace.registry.key?(name) }
    end

    def validate_or_record_unmatched(contracts, payload, provider:, event_type:, id:, strict:, record:)
      if contracts.any?
        return Hooktrace.validate(
          contracts, payload,
          strict: strict, record: record, id: id, event_type: event_type, provider: provider
        )
      end

      result = Result.new(errors: [])
      if record
        Hooktrace.store.save(
          EventRecord.new(id: id, event_type: event_type, provider: provider, valid: true, errors: [], payload: payload)
        )
      end
      result
    end
  end
end
