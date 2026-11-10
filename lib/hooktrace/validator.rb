# frozen_string_literal: true

require_relative "error"
require_relative "result"

module Hooktrace
  class Validator
    DEFAULT_MAX_ERRORS = 100

    def initialize(contract, strict: false, max_errors: DEFAULT_MAX_ERRORS)
      @contract = contract
      @strict = strict
      @max_errors = max_errors
      @errors = []
    end

    def validate(payload)
      @errors = []

      unless payload.is_a?(Hash)
        add_error("$", "type_mismatch", "Expected object/hash for payload, got #{payload.class}")
        return Result.new(errors: @errors)
      end

      validate_object(payload, @contract.fields, "")

      Result.new(errors: @errors)
    end

    private

    def validate_object(hash, fields, prefix)
      expected_names = fields.map(&:name)

      fields.each do |field|
        break if max_errors_reached?

        validate_field(hash, field, prefix)
      end

      check_unknown_fields(hash, expected_names, prefix) if @strict
    end

    def validate_field(hash, field, prefix)
      path = build_path(prefix, field.name)
      has_key, value = fetch_field_value(hash, field.name)

      unless has_key
        add_error(path, "required", "Field is required") if field.required?
        return
      end

      if value.nil?
        validate_nil_value(path, field)
        return
      end

      unless type_matches?(value, field.type)
        add_error(path, "type_mismatch", "Expected #{field.type}, got #{actual_type_name(value)}")
        return
      end

      validate_complex_field(value, field, path)
    end

    def validate_nil_value(path, field)
      return if field.nullable? || field.type == :null

      add_error(path, "type_mismatch", "Expected #{field.type}, got null")
    end

    def validate_complex_field(value, field, path)
      if field.object? && field.fields.any?
        validate_object(value, field.fields, path)
      elsif field.array? && (field.item_type || field.item_fields.any?)
        validate_array(value, field, path)
      end
    end

    def validate_array(array, field, prefix)
      array.each_with_index do |item, index|
        break if max_errors_reached?

        item_path = "#{prefix}[#{index}]"
        validate_array_item(item, field, item_path)
      end
    end

    def validate_array_item(item, field, item_path)
      if item.nil?
        unless field.nullable? || field.item_type == :null
          expected_type = field.item_type || "item"
          add_error(item_path, "type_mismatch", "Expected #{expected_type}, got null")
        end
        return
      end

      if field.item_fields.any?
        validate_array_object_item(item, field.item_fields, item_path)
      elsif field.item_type && !type_matches?(item, field.item_type)
        add_error(item_path, "type_mismatch", "Expected #{field.item_type}, got #{actual_type_name(item)}")
      end
    end

    def validate_array_object_item(item, item_fields, item_path)
      if item.is_a?(Hash)
        validate_object(item, item_fields, item_path)
      else
        add_error(item_path, "type_mismatch", "Expected object item, got #{actual_type_name(item)}")
      end
    end

    def check_unknown_fields(hash, expected_names, prefix)
      hash.each_key do |key|
        break if max_errors_reached?

        key_str = key.to_s
        next if expected_names.include?(key_str)

        path = build_path(prefix, key_str)
        add_error(path, "unknown_field", "Unknown field: #{key_str}")
      end
    end

    def max_errors_reached?
      @errors.size >= @max_errors
    end

    def fetch_field_value(hash, field_name)
      if hash.key?(field_name)
        [true, hash[field_name]]
      elsif hash.key?(field_name.to_sym)
        [true, hash[field_name.to_sym]]
      else
        [false, nil]
      end
    end

    def type_matches?(value, type)
      case type
      when :string then value.is_a?(String)
      when :integer then value.is_a?(Integer) && ![true, false].include?(value)
      when :number then value.is_a?(Numeric) && (!value.is_a?(Float) || value.finite?)
      when :boolean then [true, false].include?(value)
      when :object then value.is_a?(Hash)
      when :array then value.is_a?(Array)
      when :null then value.nil?
      else false
      end
    end

    def actual_type_name(value)
      case value
      when String then "string"
      when Integer then "integer"
      when Numeric then "number"
      when TrueClass, FalseClass then "boolean"
      when Hash then "object"
      when Array then "array"
      when NilClass then "null"
      else value.class.name.downcase
      end
    end

    def build_path(prefix, segment)
      prefix.empty? ? segment : "#{prefix}.#{segment}"
    end

    def add_error(path, code, message)
      @errors << Error.new(path: path, code: code, message: message)
    end
  end
end
