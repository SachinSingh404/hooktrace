# frozen_string_literal: true

RSpec.describe Hooktrace::EventRecord do
  it "creates an event record and serializes to hash and json" do
    record = described_class.new(
      id: "evt_100",
      event_type: "stripe.charge.succeeded",
      valid: true,
      errors: [],
      payload: { "id" => "evt_100", "amount" => 5000 }
    )

    expect(record.id).to eq("evt_100")
    expect(record.event_type).to eq("stripe.charge.succeeded")
    expect(record.provider).to eq("stripe")
    expect(record.valid?).to be true
    expect(record.errors).to be_empty

    hash = record.to_h
    expect(hash[:id]).to eq("evt_100")
    expect(hash[:valid]).to be true

    reconstructed = described_class.from_h(hash)
    expect(reconstructed.id).to eq(record.id)
    expect(reconstructed.valid?).to be true
  end
end
