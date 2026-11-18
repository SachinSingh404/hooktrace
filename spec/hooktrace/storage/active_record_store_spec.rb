# frozen_string_literal: true

require "active_record"
require "sqlite3"

RSpec.describe Hooktrace::Storage::ActiveRecordStore do
  let(:store) { described_class.new }

  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Schema.define do
      create_table :hooktrace_events, force: true do |t|
        t.string :event_id, null: false
        t.string :event_type, null: false
        t.string :provider, null: false
        t.boolean :valid_event, null: false, default: false
        t.integer :error_count, null: false, default: 0
        t.json :validation_errors
        t.json :payload
        t.datetime :received_at, null: false
        t.timestamps
      end
      add_index :hooktrace_events, :event_id, unique: true
    end
  end

  after(:each) do
    store.clear!
  end

  it "reports as available when table exists" do
    expect(described_class.available?).to be(true)
  end

  it "saves, finds, and deserializes an EventRecord" do
    record = Hooktrace::EventRecord.new(
      id: "evt_test_100",
      event_type: "charge.succeeded",
      provider: "stripe",
      valid: true,
      errors: [],
      payload: { "id" => "evt_test_100", "amount" => 5000 }
    )

    store.save(record)
    found = store.find("evt_test_100")

    expect(found).not_to be_nil
    expect(found.id).to eq("evt_test_100")
    expect(found.event_type).to eq("charge.succeeded")
    expect(found.provider).to eq("stripe")
    expect(found.valid?).to be(true)
    expect(found.payload).to eq({ "id" => "evt_test_100", "amount" => 5000 })
  end

  it "updates the existing record in-place on duplicate event_id" do
    bad_record = Hooktrace::EventRecord.new(
      id: "evt_dup_1",
      event_type: "charge.succeeded",
      provider: "stripe",
      valid: false,
      errors: [{ "path" => "amount", "code" => "required", "message" => "Field is required" }],
      payload: { "id" => "evt_dup_1" }
    )
    store.save(bad_record)
    expect(store.count).to eq(1)
    expect(store.find("evt_dup_1")).to be_invalid

    good_record = Hooktrace::EventRecord.new(
      id: "evt_dup_1",
      event_type: "charge.succeeded",
      provider: "stripe",
      valid: true,
      errors: [],
      payload: { "id" => "evt_dup_1", "amount" => 2000 }
    )
    store.save(good_record)
    expect(store.count).to eq(1)
    updated = store.find("evt_dup_1")
    expect(updated).to be_valid
    expect(updated.payload["amount"]).to eq(2000)
  end

  it "filters records by event_type and status" do
    store.save(Hooktrace::EventRecord.new(id: "e1", event_type: "order.created", valid: true))
    store.save(Hooktrace::EventRecord.new(id: "e2", event_type: "order.created", valid: false))
    store.save(Hooktrace::EventRecord.new(id: "e3", event_type: "charge.failed", valid: false))

    expect(store.all(event_type: "order.created").map(&:id)).to contain_exactly("e1", "e2")
    expect(store.all(status: "invalid").map(&:id)).to contain_exactly("e2", "e3")
    expect(store.all(status: "valid").map(&:id)).to contain_exactly("e1")
  end

  it "calculates accurate statistics and pass rate" do
    store.save(Hooktrace::EventRecord.new(id: "ok1", event_type: "test", valid: true))
    store.save(Hooktrace::EventRecord.new(id: "ok2", event_type: "test", valid: true))
    store.save(Hooktrace::EventRecord.new(id: "bad1", event_type: "test", valid: false))

    stats = store.stats
    expect(stats[:total]).to eq(3)
    expect(stats[:passed]).to eq(2)
    expect(stats[:failed]).to eq(1)
    expect(stats[:pass_rate]).to eq(66.7)
  end
end
