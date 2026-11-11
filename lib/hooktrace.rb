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

  @registry = {}
  @store = nil
  @auto_record = true

  class << self
    attr_accessor :auto_record

    def store
      @store ||= Storage::FileStore.new
    end

    def store=(new_store)
      @store = new_store
    end

    def define(name, &)
      contract = Contract.define(name, &)
      @registry[name.to_s] = contract
      contract
    end

    def contract(name)
      @registry[name.to_s] || raise(ContractNotFoundError, "Contract '#{name}' is not defined")
    end
    alias [] contract

    def validate(name_or_contracts, payload, strict: false, record: @auto_record,
                 id: nil, event_type: nil, provider: nil)
      contracts = Array(name_or_contracts).compact.map { |item| item.is_a?(Contract) ? item : contract(item) }
      all_errors = contracts.flat_map { |c| c.validate(payload, strict: strict).errors }.uniq
      result = Result.new(errors: all_errors)

      save_validation_record(result, contracts, payload, id: id, event_type: event_type, provider: provider) if record
      result
    end

    def record_and_validate(name_or_contracts, payload, strict: false, id: nil, event_type: nil, provider: nil)
      contracts = Array(name_or_contracts).compact.map { |item| item.is_a?(Contract) ? item : contract(item) }
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

    private

    def save_validation_record(result, contracts, payload, id: nil, event_type: nil, provider: nil)
      resolved_type = event_type || (contracts.last&.name)
      record = EventRecord.new(
        id: id || SecureRandom.hex(8),
        event_type: resolved_type,
        provider: provider,
        valid: result.valid?,
        errors: result.errors.map(&:to_h),
        payload: payload
      )
      store.save(record)
      record
    end
  end
end

HookTrace = Hooktrace
