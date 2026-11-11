# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Hooktrace::Storage::FileStore do
  let(:tmp_dir) { Dir.mktmpdir("hooktrace-test-") }
  subject(:store) { described_class.new(tmp_dir) }

  after { FileUtils.rm_rf(tmp_dir) }

  it "saves and retrieves event records" do
    record = Hooktrace::EventRecord.new(
      id: "evt_123",
      event_type: "charge.succeeded",
      provider: "stripe",
      valid: true,
      payload: { "id" => "evt_123" }
    )

    store.save(record)
    found = store.find("evt_123")
    expect(found).not_to be_nil
    expect(found.id).to eq("evt_123")
    expect(found.event_type).to eq("charge.succeeded")
  end
end
