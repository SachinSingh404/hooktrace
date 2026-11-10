# frozen_string_literal: true

RSpec.describe Hooktrace::Field do
  describe "#initialize" do
    it "creates an immutable field with valid types" do
      field = described_class.new(name: :id, type: :string, required: true)

      expect(field.name).to eq("id")
      expect(field.type).to eq(:string)
      expect(field.required?).to be true
      expect(field.optional?).to be false
      expect(field.nullable?).to be false
      expect(field).to be_frozen
    end

    it "raises ArgumentError on unsupported type" do
      expect do
        described_class.new(name: :foo, type: :unknown_type, required: true)
      end.to raise_error(ArgumentError, /Unsupported type/)
    end

    it "supports nullable flag" do
      field = described_class.new(name: :notes, type: :string, required: false, nullable: true)
      expect(field.nullable?).to be true
      expect(field.optional?).to be true
    end
  end
end
