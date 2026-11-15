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

    def self.override(existing_contract, &block)
      builder = Builder.new(base_fields: existing_contract.fields, allow_override: true)
      builder.instance_eval(&block) if block

      new(name: existing_contract.name, fields: builder.fields)
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

      def initialize(base_fields: [], allow_override: false)
        @fields = base_fields.dup
        @allow_override = allow_override
        @seen_names = {}
      end

      def required(name, type: nil, nullable: nil)
        add_field(name: name, type: type, required: true, nullable: nullable)
      end

      def optional(name, type: nil, nullable: nil)
        add_field(name: name, type: type, required: false, nullable: nullable)
      end

      def remove(name)
        target = name.to_s
        @fields.reject! { |f| f.name == target }
        @seen_names.delete(target)
      end

      def object(name, required: nil, nullable: nil, &block)
        existing = prepare_field_target(name)
        child_builder = Builder.new(
          base_fields: existing&.fields || [],
          allow_override: @allow_override
        )
        child_builder.instance_eval(&block) if block

        field = Field.new(
          name: name,
          type: :object,
          required: resolve_flag(required, existing, :required?, true),
          nullable: resolve_flag(nullable, existing, :nullable?, false),
          fields: child_builder.fields
        )
        upsert_field(field)
      end

      def array(name, item_type: nil, required: nil, nullable: nil, &block)
        existing = prepare_field_target(name)
        item_fields = build_array_item_fields(existing, &block)
        resolved_item_type = item_type&.to_sym || existing&.item_type

        field = Field.new(
          name: name,
          type: :array,
          required: resolve_flag(required, existing, :required?, true),
          nullable: resolve_flag(nullable, existing, :nullable?, false),
          item_type: resolved_item_type,
          item_fields: item_fields
        )
        upsert_field(field)
      end

      private

      def build_array_item_fields(existing, &block)
        return existing&.item_fields || [] unless block

        child_builder = Builder.new(
          base_fields: existing&.item_fields || [],
          allow_override: @allow_override
        )
        child_builder.instance_eval(&block)
        child_builder.fields
      end

      def add_field(name:, type:, required:, nullable:)
        existing = prepare_field_target(name)
        resolved_type = type&.to_sym || existing&.type
        raise ArgumentError, "Field type is required for '#{name}'" unless resolved_type

        field = Field.new(
          name: name,
          type: resolved_type,
          required: required,
          nullable: resolve_flag(nullable, existing, :nullable?, false)
        )
        upsert_field(field)
      end

      def resolve_flag(explicit, existing, attr, default)
        return explicit unless explicit.nil?

        existing ? existing.public_send(attr) : default
      end

      def prepare_field_target(name)
        check_duplicate!(name) unless @allow_override
        find_field(name)
      end

      def upsert_field(field)
        idx = @fields.index { |f| f.name == field.name }
        if idx
          @fields[idx] = field
        else
          @fields << field
        end
        @seen_names[field.name] = true
        field
      end

      def find_field(name)
        key = name.to_s
        @fields.find { |f| f.name == key }
      end

      def check_duplicate!(name)
        key = name.to_s
        raise ArgumentError, "Duplicate field definition: '#{name}'" if @seen_names.key?(key)
      end
    end
  end
end
