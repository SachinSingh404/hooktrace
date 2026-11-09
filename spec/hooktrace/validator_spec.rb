# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hooktrace::Validator do
  it "validates required primitive fields" do
    contract = Hooktrace::Contract.define("test.event") do
      required :id, type: :string
      required :amount, type: :integer
    end

    errors = contract.validate({ "id" => "evt_123", "amount" => 100 })
    expect(errors).to be_empty
  end

  it "reports missing required fields" do
    contract = Hooktrace::Contract.define("test.event") do
      required :id, type: :string
      required :amount, type: :integer
    end

    errors = contract.validate({ "id" => "evt_123" })
    expect(errors).to include("field 'amount' is required")
  end
end
