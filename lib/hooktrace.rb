# frozen_string_literal: true

require "securerandom"
require_relative "hooktrace/version"
require_relative "hooktrace/error"
require_relative "hooktrace/field"
require_relative "hooktrace/result"
require_relative "hooktrace/validator"
require_relative "hooktrace/contract"
require_relative "hooktrace/event_record"
require_relative "hooktrace/storage/file_store"
require_relative "hooktrace/webhook_processor"

module Hooktrace
  class StandardError < ::StandardError; end
  class ContractNotFoundError < StandardError; end

  BUILTIN_CONTRACTS_DIR = File.expand_path("hooktrace/contracts", __dir__).freeze

  @registry = {}
  @store = nil
  @auto_record = true

  class << self
    attr_accessor :auto_record

    def registry
      @registry.dup
    end

    def store
      @store ||= Storage::FileStore.new
    end

    def store=(new_store)
      @store = new_store
    end

    def configure
      yield self
    end

    def contracts_path=(directory)
      load_contracts_from(directory) if directory && Dir.exist?(directory)
    end

    def define(name, &)
      contract = Contract.define(name, &)
      @registry[name.to_s] = contract
      contract
    end

    def contract(name)
      fetch_or_load_contract(name)
    end
    alias [] contract

    def validate(name_or_contracts, payload, strict: false, record: @auto_record,
                 id: nil, event_type: nil, provider: nil)
      contracts = resolve_contracts(name_or_contracts)
      all_errors = contracts.flat_map { |c| c.validate(payload, strict: strict).errors }.uniq
      result = Result.new(errors: all_errors)

      save_validation_record(result, contracts, payload, id: id, event_type: event_type, provider: provider) if record
      result
    end

    def record_and_validate(name_or_contracts, payload, strict: false, id: nil, event_type: nil, provider: nil)
      contracts = resolve_contracts(name_or_contracts)
      all_errors = contracts.flat_map { |c| c.validate(payload, strict: strict).errors }.uniq
      result = Result.new(errors: all_errors)

      record = save_validation_record(result, contracts, payload, id: id, event_type: event_type, provider: provider)
      [result, record]
    end

    def process_webhook(payload_or_raw, headers: {}, provider: nil, event_type: nil, id: nil,
                        strict: false, record: @auto_record)
      WebhookProcessor.process(
        payload_or_raw,
        headers: headers,
        provider: provider,
        event_type: event_type,
        id: id,
        strict: strict,
        record: record
      )
    end
    alias handle_webhook process_webhook

    def load_contract(path)
      content = File.read(path, encoding: "UTF-8")
      data = JSON.parse(content)
      contracts = parse_contracts_data(data)

      contracts.each { |c| @registry[c.name] = c }
      single_contract?(data, contracts) ? contracts.first : contracts
    end

    def load_contracts_from(directory)
      pattern = File.join(directory, "**", "*.json")
      Dir.glob(pattern).flat_map { |file| Array(load_contract(file)) }
    end

    def clear_registry!
      @registry.clear
    end

    private

    def parse_contracts_data(data)
      if data.is_a?(Array)
        data.map { |item| Contract.from_h(item) }
      elsif data.key?("events") || data.key?("contracts")
        list = data["events"] || data["contracts"]
        prefix = data["provider"]
        list.map do |item|
          item["name"] = "#{prefix}.#{item["name"]}" if prefix && !item["name"].start_with?("#{prefix}.")
          Contract.from_h(item)
        end
      elsif data.key?("fields")
        [Contract.from_h(data)]
      else
        data.map do |name, definition|
          Contract.from_h(definition.merge("name" => name))
        end
      end
    end

    def fetch_or_load_contract(name)
      str_name = name.to_s
      return @registry[str_name] if @registry.key?(str_name)

      provider = str_name.split(".").first
      builtin_file = File.join(BUILTIN_CONTRACTS_DIR, "#{provider}.json")
      load_contract(builtin_file) if File.exist?(builtin_file)

      @registry[str_name] || raise(ContractNotFoundError, "Contract '#{name}' is not defined")
    end

    def single_contract?(data, contracts)
      contracts.size == 1 && !data.is_a?(Array) && !data.key?("events") && !data.key?("contracts")
    end

    def resolve_contracts(name_or_contracts)
      Array(name_or_contracts).compact.map do |item|
        item.is_a?(Contract) ? item : contract(item)
      end
    end

    def save_validation_record(result, contracts, payload, id: nil, event_type: nil, provider: nil)
      resolved_type = event_type || resolve_event_type(contracts, payload)
      record = EventRecord.new(
        id: id || extract_event_id(payload),
        event_type: resolved_type,
        provider: provider,
        valid: result.valid?,
        errors: result.errors.map(&:to_h),
        payload: payload
      )
      store.save(record)
      record
    end

    def resolve_event_type(contracts, payload)
      specific = contracts.last&.name
      return specific unless specific&.end_with?(".event.base") && payload.is_a?(Hash)

      payload["type"] || payload[:type] || payload["event_type"] || payload[:event_type] || specific
    end

    def extract_event_id(payload)
      return SecureRandom.hex(8) unless payload.is_a?(Hash)

      (payload["id"] || payload[:id] || SecureRandom.hex(8)).to_s
    end
  end
end

HookTrace = Hooktrace
