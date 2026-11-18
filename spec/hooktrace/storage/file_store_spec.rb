# frozen_string_literal: true

require "tmpdir"

RSpec.describe Hooktrace::Storage::FileStore do
  let(:temp_dir) { Dir.mktmpdir("hooktrace_test") }
  let(:store) { described_class.new(temp_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  it "saves, finds, counts, and clears records" do
    record = Hooktrace::EventRecord.new(
      id: "evt_test_1",
      event_type: "charge.succeeded",
      valid: true,
      payload: { "amount" => 2000 }
    )

    store.save(record)
    expect(store.count).to eq(1)

    found = store.find("evt_test_1")
    expect(found).not_to be_nil
    expect(found.id).to eq("evt_test_1")
    expect(found.event_type).to eq("charge.succeeded")
    expect(found.valid?).to be true

    stats = store.stats
    expect(stats[:total]).to eq(1)
    expect(stats[:passed]).to eq(1)
    expect(stats[:failed]).to eq(0)
    expect(stats[:pass_rate]).to eq(100.0)

    store.clear!
    expect(store.count).to eq(0)
  end

  it "upserts by id instead of creating duplicate files" do
    bad = Hooktrace::EventRecord.new(id: "evt_dup", event_type: "stripe.charge.succeeded", valid: false, payload: {})
    store.save(bad)
    expect(store.count).to eq(1)

    fixed = Hooktrace::EventRecord.new(id: "evt_dup", event_type: "stripe.charge.succeeded", valid: true, payload: {})
    store.save(fixed)
    expect(store.count).to eq(1)
    expect(store.find("evt_dup")).to be_valid
  end
end
