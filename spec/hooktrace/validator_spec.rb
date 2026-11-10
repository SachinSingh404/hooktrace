# frozen_string_literal: true

RSpec.describe Hooktrace::Validator do
  let(:contract) do
    Hooktrace::Contract.define("stripe.payment") do
      required :id, type: :string
      required :amount, type: :integer
      optional :description, type: :string, nullable: true
      optional :livemode, type: :boolean

      object :customer, required: false do
        required :email, type: :string
        optional :phone, type: :string
      end

      array :tags, item_type: :string, required: false
    end
  end

  describe "basic validation" do
    it "validates a matching payload with string keys" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "description" => "Payment for invoice",
        "livemode" => true
      }

      result = contract.validate(payload)
      expect(result).to be_valid
      expect(result.errors).to be_empty
    end

    it "validates a matching payload with symbol keys" do
      payload = {
        id: "ch_123",
        amount: 2000,
        livemode: false
      }

      result = contract.validate(payload)
      expect(result).to be_valid
    end

    it "fails if payload is not a hash" do
      result = contract.validate("not_a_hash")
      expect(result).not_to be_valid
      expect(result.errors.first.code).to eq("type_mismatch")
      expect(result.errors.first.path).to eq("$")
    end

    it "catches missing required fields" do
      payload = {
        "amount" => 2000
      }

      result = contract.validate(payload)
      expect(result).not_to be_valid
      expect(result.errors.size).to eq(1)

      error = result.errors.first
      expect(error.path).to eq("id")
      expect(error.code).to eq("required")
    end

    it "catches type mismatches" do
      payload = {
        "id" => "ch_123",
        "amount" => "2000" # string instead of integer
      }

      result = contract.validate(payload)
      expect(result).not_to be_valid

      error = result.errors.first
      expect(error.path).to eq("amount")
      expect(error.code).to eq("type_mismatch")
      expect(error.message).to include("Expected integer")
    end
  end

  describe "nullable and null handling" do
    it "allows nil for nullable fields" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "description" => nil
      }

      result = contract.validate(payload)
      expect(result).to be_valid
    end

    it "rejects nil for non-nullable fields" do
      payload = {
        "id" => nil,
        "amount" => 2000
      }

      result = contract.validate(payload)
      expect(result).not_to be_valid
      expect(result.errors.first.path).to eq("id")
      expect(result.errors.first.code).to eq("type_mismatch")
    end
  end

  describe "nested objects" do
    it "validates valid nested objects" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "customer" => {
          "email" => "customer@example.com",
          "phone" => "+1234567890"
        }
      }

      result = contract.validate(payload)
      expect(result).to be_valid
    end

    it "reports errors with nested paths" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "customer" => {
          "email" => 12_345 # expected string
        }
      }

      result = contract.validate(payload)
      expect(result).not_to be_valid
      expect(result.errors.first.path).to eq("customer.email")
      expect(result.errors.first.code).to eq("type_mismatch")
    end
  end

  describe "arrays" do
    it "validates array items" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "tags" => %w[vip urgent]
      }

      result = contract.validate(payload)
      expect(result).to be_valid
    end

    it "catches invalid items in array with indexed path" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "tags" => ["vip", 999]
      }

      result = contract.validate(payload)
      expect(result).not_to be_valid
      expect(result.errors.first.path).to eq("tags[1]")
      expect(result.errors.first.code).to eq("type_mismatch")
    end
  end

  describe "strict mode" do
    it "allows unknown fields by default (permissive mode)" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "extra_field" => "some value"
      }

      result = contract.validate(payload, strict: false)
      expect(result).to be_valid
    end

    it "rejects unknown fields when strict: true" do
      payload = {
        "id" => "ch_123",
        "amount" => 2000,
        "extra_field" => "some value"
      }

      result = contract.validate(payload, strict: true)
      expect(result).not_to be_valid
      expect(result.errors.first.path).to eq("extra_field")
      expect(result.errors.first.code).to eq("unknown_field")
    end
  end
end
