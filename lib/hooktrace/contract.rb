# frozen_string_literal: true

require "json"
require_relative "field"
require_relative "validator"

module Hooktrace
  class Contract
    attr_reader :name, :fields

    def self.define(name, &block)
      builder = Builder.new
      builder.instance_eval(&block) if block

      new(name: name, fields: builder.fields)
    end

    def self.from_h(hash)
      data = hash.transform_keys(&:to_s)
      fields = (data["fields"] || []).map { |f| parse_field_hash(f) }
      new(name: data.fetch("name", "anonymous"), fields: fields)
    end

    def self.from_json(json_str)
      from_h(JSON.parse(json_str))
    end

    def self.parse_field_hash(hash)
      data = hash.transform_keys(&:to_s)
      Field.new(
        name: data["name"],
        type: data["type"]&.to_sym,
        required: data.fetch("required", true),
        nullable: data.fetch("nullable", false),
        fields: (data["fields"] || []).map { |f| parse_field_hash(f) },
        item_type: data["item_type"]&.to_sym,
        item_fields: (data["item_fields"] || []).map { |f| parse_field_hash(f) }
      )
    end
    private_class_method :parse_field_hash

    def initialize(name:, fields:)
      @name = name.to_s.freeze
      @fields = fields.freeze
      freeze
    end

    def validate(payload, strict: false, max_errors: Validator::DEFAULT_MAX_ERRORS)
      Validator.new(self, strict: strict, max_errors: max_errors).validate(payload)
    end

    def to_h
      {
        name: name,
        fields: fields.map { |f| field_to_h(f) }
      }
    end

    def to_json(*args)
      JSON.generate(to_h, *args)
    end

    private

    def field_to_h(field)
      h = {
        name: field.name,
        type: field.type,
        required: field.required?,
        nullable: field.nullable?
      }
      h[:item_type] = field.item_type if field.item_type
      h[:item_fields] = field.item_fields.map { |f| field_to_h(f) } if field.item_fields.any?
      h[:fields] = field.fields.map { |f| field_to_h(f) } if field.fields.any?
      h
    end

    class Builder
      attr_reader :fields

      def initialize
        @fields = []
      end

      def required(name, type: nil, nullable: false)
        @fields << Field.new(name: name, type: type&.to_sym, required: true, nullable: nullable)
      end

      def optional(name, type: nil, nullable: false)
        @fields << Field.new(name: name, type: type&.to_sym, required: false, nullable: nullable)
      end

      def object(name, required: true, nullable: false, &block)
        child_builder = Builder.new
        child_builder.instance_eval(&block) if block
        @fields << Field.new(
          name: name,
          type: :object,
          required: required,
          nullable: nullable,
          fields: child_builder.fields
        )
      end

      def array(name, item_type: nil, required: true, nullable: false, &block)
        item_fields = []
        if block
          child_builder = Builder.new
          child_builder.instance_eval(&block)
          item_fields = child_builder.fields
        end

        @fields << Field.new(
          name: name,
          type: :array,
          required: required,
          nullable: nullable,
          item_type: item_type&.to_sym,
          item_fields: item_fields
        )
      end
    end
  end
end
