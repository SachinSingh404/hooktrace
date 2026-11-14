# frozen_string_literal: true

require "json"

module Hooktrace
  module Storage
    class ActiveRecordStore
      def self.available?
        return false unless defined?(::ActiveRecord::Base)

        ::ActiveRecord::Base.connection_pool.with_connection do |conn|
          conn.table_exists?("hooktrace_events")
        end
      rescue ::StandardError
        false
      end

      def model_class
        return self.class.const_get(:Event, false) if self.class.const_defined?(:Event, false)

        unless defined?(::ActiveRecord::Base)
          raise Hooktrace::StandardError, "ActiveRecord::Base is required for ActiveRecordStore"
        end

        klass = Class.new(::ActiveRecord::Base) do
          self.table_name = "hooktrace_events"
        end
        self.class.const_set(:Event, klass)
      end

      def save(record)
        rec = record.is_a?(EventRecord) ? record : EventRecord.from_h(record)
        attributes = {
          event_type: rec.event_type,
          provider: rec.provider,
          valid_event: rec.valid?,
          error_count: rec.errors.size,
          validation_errors: serialize_json_column(:validation_errors, rec.errors),
          payload: serialize_json_column(:payload, rec.payload),
          received_at: parse_time(rec.received_at)
        }

        row = model_class.find_or_initialize_by(event_id: rec.id)
        row.update!(attributes)
        rec
      end

      def find(id)
        id_str = id.to_s
        row = model_class.where(event_id: id_str).order(received_at: :desc, id: :desc).first
        row ||= model_class.find_by(id: id_str) if id_str.match?(/\A\d+\z/)
        row ? to_event_record(row) : nil
      end

      def all(limit: 100, event_type: nil, status: nil)
        scope = model_class.order(received_at: :desc, id: :desc)
        scope = scope.where(event_type: event_type) if event_type && !event_type.empty?
        scope = scope.where(valid_event: status == "valid") if status && !status.empty?

        scope.limit(limit).map { |row| to_event_record(row) }
      end

      def count
        model_class.count
      end

      def stats
        total = model_class.count
        passed = model_class.where(valid_event: true).count
        failed = total - passed
        rate = total.positive? ? ((passed.to_f / total) * 100).round(1) : 100.0

        {
          total: total,
          passed: passed,
          failed: failed,
          pass_rate: rate
        }
      end

      def clear!
        model_class.delete_all
      end

      private

      def to_event_record(row)
        EventRecord.new(
          id: row.event_id,
          event_type: row.event_type,
          provider: row.provider,
          received_at: row.received_at&.utc&.iso8601,
          valid: row.valid_event,
          errors: deserialize_json_column(row.validation_errors, []),
          payload: deserialize_json_column(row.payload, {})
        )
      end

      def serialize_json_column(column_name, value)
        col = model_class.columns_hash[column_name.to_s]
        if col && %i[json jsonb].include?(col.type)
          value
        else
          JSON.generate(value)
        end
      end

      def deserialize_json_column(value, fallback)
        return fallback if value.nil?
        return value unless value.is_a?(String)

        JSON.parse(value)
      rescue JSON::ParserError
        fallback
      end

      def parse_time(value)
        return value if value.is_a?(Time)

        Time.parse(value.to_s).utc
      rescue ArgumentError
        Time.now.utc
      end
    end
  end
end
