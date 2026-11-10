# frozen_string_literal: true

module Hooktrace
  class Field
    TYPES = %i[
      string integer number boolean object array null
    ].freeze

    attr_reader :name, :type, :required, :nullable, :fields, :item_type, :item_fields

    def initialize(name:, type:, required: true, nullable: false, fields: [], item_type: nil, item_fields: [])
      unless TYPES.include?(type)
        raise ArgumentError, "Unsupported type: #{type.inspect}. Supported types are #{TYPES.map(&:inspect).join(", ")}"
      end

      @name = name.to_s.freeze
      @type = type
      @required = !required.nil? && required != false
      @nullable = !nullable.nil? && nullable != false
      @fields = fields.freeze
      @item_type = item_type
      @item_fields = item_fields.freeze
      freeze
    end

    def required?
      @required
    end

    def optional?
      !@required
    end

    def nullable?
      @nullable
    end

    def object?
      @type == :object
    end

    def array?
      @type == :array
    end
  end
end
