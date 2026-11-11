# frozen_string_literal: true

RSpec.describe Hooktrace::Contract do
  describe ".define" do
    it "defines a contract with required and optional fields" do
      contract = described_class.define("payment.succeeded") do
        required :id, type: :string
        required :amount, type: :integer
        optional :currency, type: :string
      end

      expect(contract.name).to eq("payment.succeeded")
      expect(contract.fields.size).to eq(3)
      expect(contract.fields.map(&:name)).to eq(%w[id amount currency])
      expect(contract).to be_frozen
    end

    it "raises ArgumentError when duplicate fields are defined" do
      expect do
        described_class.define("duplicate.test") do
          required :id, type: :string
          optional :id, type: :string
        end
      end.to raise_error(ArgumentError, /Duplicate field definition: 'id'/)
    end

    it "supports nested objects" do
      contract = described_class.define("nested.test") do
        required :id, type: :string
        object :customer do
          required :email, type: :string
          optional :name, type: :string
        end
      end

      customer_field = contract.fields.find { |f| f.name == "customer" }
      expect(customer_field.type).to eq(:object)
      expect(customer_field.fields.size).to eq(2)
      expect(customer_field.fields.map(&:name)).to eq(%w[email name])
    end

    it "supports arrays with item types" do
      contract = described_class.define("array.test") do
        array :tags, item_type: :string
        array :line_items do
          required :sku, type: :string
          required :qty, type: :integer
        end
      end

      tags = contract.fields.find { |f| f.name == "tags" }
      expect(tags.type).to eq(:array)
      expect(tags.item_type).to eq(:string)

      items = contract.fields.find { |f| f.name == "line_items" }
      expect(items.type).to eq(:array)
      expect(items.item_fields.map(&:name)).to eq(%w[sku qty])
    end
  end

  describe "serialization" do
    it "serializes to hash/json and reconstructs with from_h / from_json" do
      original = described_class.define("order.created") do
        required :order_id, type: :string
        required :total, type: :number
        object :billing do
          required :city, type: :string
        end
        array :items, item_type: :string
      end

      json_str = original.to_json
      reconstructed = described_class.from_json(json_str)

      expect(reconstructed.name).to eq("order.created")
      expect(reconstructed.fields.map(&:name)).to eq(original.fields.map(&:name))

      billing = reconstructed.fields.find { |f| f.name == "billing" }
      expect(billing.fields.first.name).to eq("city")

      items = reconstructed.fields.find { |f| f.name == "items" }
      expect(items.item_type).to eq(:string)
    end
  end

  describe ".override" do
    it "merges, updates, and removes fields on an existing contract" do
      base = described_class.define("stripe.charge.succeeded") do
        required :id, type: :string
        optional :legacy_note, type: :string
        object :data do
          object :object do
            required :amount, type: :integer
            optional :customer, type: :string, nullable: true
          end
        end
      end

      overridden = described_class.override(base) do
        remove :legacy_note
        object :data do
          object :object do
            required :customer, nullable: false
            optional :tenant_id, type: :string
          end
        end
      end

      expect(overridden.fields.map(&:name)).not_to include("legacy_note")
      obj_fields = overridden.fields.find { |f| f.name == "data" }.fields.first.fields
      customer = obj_fields.find { |f| f.name == "customer" }
      expect(customer).to be_required
      expect(customer).not_to be_nullable
      expect(obj_fields.map(&:name)).to include("amount", "customer", "tenant_id")
    end
  end
end
