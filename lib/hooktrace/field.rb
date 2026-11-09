# frozen_string_literal: true

module Hooktrace
  class Field
    TYPES = %i[
      string integer number boolean null
    ].freeze

    attr_reader :name, :type, :required, :nullable

    def initialize(name:, type:, required: true, nullable: false)
      unless TYPES.include?(type)
        raise ArgumentError, "Unsupported type: #{type.inspect}. Supported types are #{TYPES.map(&:inspect).join(", ")}"
      end

      @name = name.to_s.freeze
      @type = type
      @required = !required.nil? && required != false
      @nullable = !nullable.nil? && nullable != false
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
  end
end
