# frozen_string_literal: true

require_relative "hooktrace/version"
require_relative "hooktrace/field"
require_relative "hooktrace/contract"

module Hooktrace
  class StandardError < ::StandardError; end
  class ContractNotFoundError < StandardError; end

  @registry = {}

  class << self
    def define(name, &)
      contract = Contract.define(name, &)
      @registry[name.to_s] = contract
      contract
    end

    def contract(name)
      @registry[name.to_s] || raise(ContractNotFoundError, "Contract '#{name}' is not defined")
    end
    alias [] contract
  end
end

HookTrace = Hooktrace
