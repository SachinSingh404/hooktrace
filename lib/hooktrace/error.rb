# frozen_string_literal: true

module Hooktrace
  class Error
    attr_reader :path, :code, :message

    def initialize(path:, code:, message:)
      @path = path.freeze
      @code = code.freeze
      @message = message.freeze
      freeze
    end

    def to_h
      {
        path: path,
        code: code,
        message: message
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        path == other.path &&
        code == other.code &&
        message == other.message
    end
    alias eql? ==

    def hash
      [path, code, message].hash
    end

    def to_s
      "#{path}: [#{code}] #{message}"
    end
  end
end
