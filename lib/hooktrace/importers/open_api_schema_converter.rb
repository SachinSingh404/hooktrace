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

      def build_fields(schema_or_ref, schemas, depth:, visited:, extra_required: [])
        return [] if depth > @max_depth

        properties, required_list, next_visited = collect_object_schema(schema_or_ref, schemas, visited)
        return [] if properties.empty?

        required_set = Set.new((required_list + extra_required).map(&:to_s))

        properties.keys.sort.map do |prop_name|
          convert_property(
            prop_name,
            properties[prop_name],
            schemas,
            required: required_set.include?(prop_name),
            depth: depth,
            visited: next_visited
          )
        end
      end

      private

      def collect_object_schema(schema_or_ref, schemas, visited)
        schema, next_visited = resolve_schema(schema_or_ref, schemas, visited)
        return [{}, [], next_visited] unless schema.is_a?(Hash)

        props = {}
        reqs = []

        Array(schema["allOf"]).each do |sub|
          sub_props, sub_reqs, next_visited = collect_object_schema(sub, schemas, next_visited)
          props.merge!(sub_props)
          reqs.concat(sub_reqs)
        end

        props.merge!(schema["properties"]) if schema["properties"].is_a?(Hash)
        reqs.concat(schema["required"]) if schema["required"].is_a?(Array)

        [props, reqs.uniq, next_visited]
      end

      def convert_property(name, prop_schema, schemas, required:, depth:, visited:)
        nullable = prop_schema.is_a?(Hash) && prop_schema["nullable"] == true
        effective_schema, next_visited = unwrap_combinators(prop_schema, schemas, visited)
        nullable ||= effective_schema["nullable"] == true

        field_type = map_type(effective_schema, schemas, next_visited)
        result = {
          "name" => name,
          "type" => field_type,
          "required" => required,
          "nullable" => nullable
        }

        if field_type == "object" && depth < @max_depth
          nested = build_fields(effective_schema, schemas, depth: depth + 1, visited: next_visited)
          result["fields"] = nested unless nested.empty?
        elsif field_type == "array"
          apply_array_metadata(result, effective_schema, schemas, depth: depth, visited: next_visited)
        end

        result
      end

      def apply_array_metadata(result, array_schema, schemas, depth:, visited:)
        items = array_schema["items"]
        return unless items.is_a?(Hash)

        resolved_item, next_visited = unwrap_combinators(items, schemas, visited)
        item_type = map_type(resolved_item, schemas, next_visited)
        result["item_type"] = item_type

        return unless item_type == "object" && depth < @max_depth

        item_fields = build_fields(resolved_item, schemas, depth: depth + 1, visited: next_visited)
        result["item_fields"] = item_fields unless item_fields.empty?
      end

      def resolve_schema(schema_or_ref, schemas, visited)
        return [{}, visited] unless schema_or_ref.is_a?(Hash)

        if schema_or_ref["$ref"]
          ref_name = schema_or_ref["$ref"].split("/").last
          return [{}, visited] if visited.include?(ref_name)

          target = schemas[ref_name] || {}
          return resolve_schema(target, schemas, visited + [ref_name])
        end

        [schema_or_ref, visited]
      end

      def unwrap_combinators(prop_schema, schemas, visited)
        return resolve_schema(prop_schema, schemas, visited) unless prop_schema.is_a?(Hash)

        variants = prop_schema["anyOf"] || prop_schema["oneOf"]
        if variants.is_a?(Array) && !variants.empty?
          primitive = variants.find { |v| v.is_a?(Hash) && v["type"] && v["type"] != "null" && !v.key?("$ref") }
          return [primitive, visited] if primitive

          non_null = variants.find { |v| v.is_a?(Hash) && v["type"] != "null" }
          return resolve_schema(non_null, schemas, visited) if non_null
        end

        resolve_schema(prop_schema, schemas, visited)
      end

      def map_type(schema, schemas = {}, visited = Set.new)
        resolved, next_visited = resolve_schema(schema, schemas, visited)
        explicit = resolved["type"]
        return explicit if %w[integer number boolean array object string].include?(explicit)

        props, = collect_object_schema(resolved, schemas, next_visited)
        return "object" if props.any?

        Array(resolved["allOf"]).each do |sub|
          sub_type = map_type(sub, schemas, next_visited)
          return sub_type if %w[integer number boolean array object string].include?(sub_type)
        end

        "string"
      end
    end
  end
end
