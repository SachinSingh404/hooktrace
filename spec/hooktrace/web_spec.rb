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
  end

  it "renders contracts catalog" do
    get "/contracts"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Contracts")
  end
end
