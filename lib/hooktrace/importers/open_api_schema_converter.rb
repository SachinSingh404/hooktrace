# frozen_string_literal: true

require "json"
require "net/http"
require "set"
require "uri"

module Hooktrace
  module Importers
    class OpenApiSchemaConverter
      def self.load_spec(source)
        raw = if source.start_with?("http://", "https://")
                fetch_http(source)
              else
                File.read(source, encoding: "UTF-8")
              end
        JSON.parse(raw)
      end

      def self.fetch_http(url, limit = 5)
        raise Hooktrace::StandardError, "Too many HTTP redirects fetching #{url}" if limit.zero?

        res = Net::HTTP.get_response(URI(url))
        return res.body if res.is_a?(Net::HTTPSuccess)
        return fetch_http(res["location"], limit - 1) if res.is_a?(Net::HTTPRedirection) && res["location"]

        raise Hooktrace::StandardError, "Failed to fetch OpenAPI spec (#{res.code} #{res.message}) from #{url}"
      end

      def initialize(max_depth: 2)
        @max_depth = max_depth
      end

      def map_type(schema)
        type = schema["type"]
        case type
        when "string" then :string
        when "integer" then :integer
        when "number" then :number
        when "boolean" then :boolean
        when "array" then :array
        when "object" then :object
        else :string
        end
      end
    end
  end
end
