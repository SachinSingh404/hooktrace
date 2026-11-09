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

      @contract.fields.each do |field|
        has_key, value = fetch_field_value(payload, field.name)

        unless has_key
          @errors << "field '#{field.name}' is required" if field.required?
          next
        end

        if value.nil?
          @errors << "field '#{field.name}' expected #{field.type}, got null" unless field.nullable? || field.type == :null
          next
        end

        unless type_matches?(value, field.type)
          @errors << "field '#{field.name}' expected #{field.type}, got #{value.class.name.downcase}"
        end
      end

      @errors
    end

    private

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
      when :null then value.nil?
      else false
      end
    end
  end
end
