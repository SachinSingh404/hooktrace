# frozen_string_literal: true

module Hooktrace
  class Validator
    def initialize(contract)
      @contract = contract
      @errors = []
    end

    def validate(payload)
      @errors = []

      unless payload.is_a?(Hash)
        @errors << "Payload must be a Hash"
        return @errors
      end

      validate_object(payload, @contract.fields, "")
      @errors
    end

    private

    def validate_object(hash, fields, prefix)
      fields.each do |field|
        validate_field(hash, field, prefix)
      end
    end

    def validate_field(hash, field, prefix)
      path = build_path(prefix, field.name)
      has_key, value = fetch_field_value(hash, field.name)

      unless has_key
        @errors << "field '#{path}' is required" if field.required?
        return
      end

      if value.nil?
        @errors << "field '#{path}' expected #{field.type}, got null" unless field.nullable? || field.type == :null
        return
      end

      unless type_matches?(value, field.type)
        @errors << "field '#{path}' expected #{field.type}, got #{actual_type_name(value)}"
        return
      end

      validate_complex_field(value, field, path)
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
        item_path = "#{prefix}[#{index}]"
        validate_array_item(item, field, item_path)
      end
    end

    def validate_array_item(item, field, item_path)
      if item.nil?
        @errors << "field '#{item_path}' expected #{field.item_type || 'item'}, got null" unless field.nullable? || field.item_type == :null
        return
      end

      if field.item_fields.any?
        if item.is_a?(Hash)
          validate_object(item, field.item_fields, item_path)
        else
          @errors << "field '#{item_path}' expected object item, got #{actual_type_name(item)}"
        end
      elsif field.item_type && !type_matches?(item, field.item_type)
        @errors << "field '#{item_path}' expected #{field.item_type}, got #{actual_type_name(item)}"
      end
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
      when :number then value.is_a?(Numeric)
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
  end
end
