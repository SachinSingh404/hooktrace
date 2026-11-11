# frozen_string_literal: true

require "json"
require "time"

module Hooktrace
  class EventRecord
    attr_reader :id, :event_type, :provider, :received_at, :valid, :errors, :payload

    def self.from_h(hash)
      data = hash.transform_keys(&:to_s)
      new(
        id: data.fetch("id"),
        event_type: data.fetch("event_type"),
        provider: data["provider"],
        received_at: data["received_at"],
        valid: data.fetch("valid", false),
        errors: data["errors"] || [],
        payload: data["payload"] || {}
      )
    end

    def initialize(id:, event_type:, valid:, errors: [], payload: {}, provider: nil, received_at: nil)
      @id = id.to_s.freeze
      @event_type = event_type.to_s.freeze
      @provider = (provider || detect_provider(@event_type, payload)).to_s.freeze
      @received_at = (received_at || Time.now.utc.iso8601).to_s.freeze
      @valid = [true, "true"].include?(valid)
      @errors = errors.freeze
      @payload = payload.freeze
      freeze
    end

    def valid?
      @valid
    end

    def invalid?
      !@valid
    end

    def to_h
      {
        id: id,
        event_type: event_type,
        provider: provider,
        received_at: received_at,
        valid: valid?,
        error_count: errors.size,
        errors: errors,
        payload: payload
      }
    end

    def to_json(*args)
      JSON.generate(to_h, *args)
    end

    private

    def detect_provider(type, payload)
      if type.start_with?("stripe.") || payload["object"] == "event"
        "stripe"
      elsif type.start_with?("paypal.") || payload["resource_type"]
        "paypal"
      else
        "unknown"
      end
    end
  end
end
