# frozen_string_literal: true

require "json"

module Hooktrace
  class Result
    attr_reader :errors

    def initialize(errors: [])
      @errors = errors.freeze
      freeze
    end

    def valid?
      @errors.empty?
    end

    def invalid?
      !valid?
    end

    def to_h
      {
        valid: valid?,
        error_count: errors.size,
        errors: errors.map(&:to_h)
      }
    end

    def to_json(*args)
      JSON.generate(to_h, *args)
    end

    def inspect
      "#<#{self.class.name} valid=#{valid?} errors=#{errors.size}>"
    end
  end
end
