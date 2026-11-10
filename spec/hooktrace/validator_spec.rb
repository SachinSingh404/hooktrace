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

  it "validates nested objects" do
    contract = Hooktrace::Contract.define("user.created") do
      required :id, type: :string
      object :profile do
        required :first_name, type: :string
        required :age, type: :integer
      end
    end

    errors = contract.validate({
      "id" => "usr_1",
      "profile" => { "first_name" => "Sachin", "age" => "not_int" }
    })
    expect(errors).to include("field 'profile.age' expected integer, got string")
  end

  it "validates array items" do
    contract = Hooktrace::Contract.define("order.placed") do
      array :items, item_type: :string
    end

    errors = contract.validate({ "items" => ["apple", 123] })
    expect(errors).to include("field 'items[1]' expected string, got integer")
  end
end
