# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe Hooktrace::Web do
  include Rack::Test::Methods

  def app
    described_class
  end

  before do
    Hooktrace.store.clear!
  end

  it "renders dashboard events page" do
    get "/events"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Webhook Events")
    it "renders individual event details" do
    Hooktrace.store.save(Hooktrace::EventRecord.new(
      id: "evt_inspect",
      event_type: "payment.created",
      provider: "stripe",
      valid: true,
      payload: { "id" => "evt_inspect" }
    ))

    get "/events/evt_inspect"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("evt_inspect")
  end

  it "renders contracts catalog" do
    get "/contracts"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Contracts")
  end
end
