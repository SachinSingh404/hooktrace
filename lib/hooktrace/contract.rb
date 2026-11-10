# frozen_string_literal: true

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

    def initialize(name:, fields:)
      @name = name.to_s.freeze
      @fields = fields.freeze
      freeze
    end

    def validate(payload)
      Validator.new(self).validate(payload)
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
