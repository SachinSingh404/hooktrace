# frozen_string_literal: true

require "fileutils"
require "json"

module Hooktrace
  module Storage
    class FileStore
      DEFAULT_DIR = "tmp/hooktrace/events"

      attr_reader :directory

      def initialize(directory = DEFAULT_DIR)
        @directory = File.expand_path(directory)
        @mutex = Monitor.new
        ensure_directory!
      end

      def save(record)
        ensure_directory!
        rec = record.is_a?(EventRecord) ? record : EventRecord.from_h(record)
        safe_id = sanitize_filename(rec.id)
        filename = "#{sanitize_filename(rec.received_at)}_#{safe_id}.json"
        filepath = File.join(@directory, filename)

        @mutex.synchronize do
          FileUtils.rm_f(Dir.glob(File.join(@directory, "*_#{safe_id}.json")))
          File.write(filepath, JSON.pretty_generate(rec.to_h))
        end
        rec
      end

      def find(id)
        id_str = sanitize_filename(id)
        pattern = File.join(@directory, "*_#{id_str}.json")
        file = Dir.glob(pattern).first
        return nil unless file && File.exist?(file)

        data = JSON.parse(File.read(file))
        EventRecord.from_h(data)
      rescue JSON::ParserError
        nil
      end

      def all(limit: 100, event_type: nil, status: nil)
        ensure_directory!
        files = Dir.glob(File.join(@directory, "*.json")).reverse
        records = files.lazy.map do |file|
          load_file(file)
        end.compact

        records = records.select { |r| r.event_type == event_type } if event_type
        records = records.select { |r| status == "valid" ? r.valid? : r.invalid? } if status

        records.take(limit).to_a
      end

      def count
        ensure_directory!
        Dir.glob(File.join(@directory, "*.json")).size
      end

      def stats
        records = all(limit: 500)
        total = records.size
        passed = records.count(&:valid?)
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
        ensure_directory!
        @mutex.synchronize do
          FileUtils.rm_f(Dir.glob(File.join(@directory, "*.json")))
        end
      end

      private

      def ensure_directory!
        FileUtils.mkdir_p(@directory) unless File.directory?(@directory)
      end

      def load_file(file)
        data = JSON.parse(File.read(file))
        EventRecord.from_h(data)
      rescue StandardError
        nil
      end

      def sanitize_filename(string)
        string.to_s.gsub(/[^0-9A-Za-z_-]/, "_")
      end
    end
  end
end
