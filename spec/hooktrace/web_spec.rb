# frozen_string_literal: true

require "rack/mock"

RSpec.describe Hooktrace::Web do
  let(:app) { described_class.new }
  let(:mock_request) { Rack::MockRequest.new(app) }
  let(:temp_dir) { Dir.mktmpdir("hooktrace_web_test") }

  before do
    Hooktrace.store = Hooktrace::Storage::FileStore.new(temp_dir)
    Hooktrace.clear_registry!
    Hooktrace.define("order.completed") do
      required :order_id, type: :string
    end
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  it "renders the events list page" do
    res = mock_request.get("/events")
    expect(res.status).to eq(200)
    expect(res.body).to include("Hooktrace")
    expect(res.body).to include("Captured Webhook Payloads")
  end

  it "renders the contracts page" do
    res = mock_request.get("/contracts")
    expect(res.status).to eq(200)
    expect(res.body).to include("order.completed")
  end

  it "renders an event detail page" do
    record = Hooktrace::EventRecord.new(
      id: "evt_inspect_1",
      event_type: "order.completed",
      valid: true,
      payload: { "order_id" => "ord_999" }
    )
    Hooktrace.store.save(record)

    res = mock_request.get("/events/evt_inspect_1")
    expect(res.status).to eq(200)
    expect(res.body).to include("order.completed")
    expect(res.body).to include("ord_999")
  end

  it "clears events via POST /events/clear" do
    record = Hooktrace::EventRecord.new(
      id: "evt_del",
      event_type: "order.completed",
      valid: true,
      payload: {}
    )
    Hooktrace.store.save(record)
    expect(Hooktrace.store.count).to eq(1)

    res = mock_request.post("/events/clear")
    expect(res.status).to eq(302)
    expect(Hooktrace.store.count).to eq(0)
  end

  it "revalidates an invalid event and failed events from the dashboard" do
    Hooktrace.define("paypal.PAYMENT.CAPTURE.COMPLETED") do
      required :id, type: :string
      required :legacy_key, type: :string
    end

    bad_record = Hooktrace::EventRecord.new(
      id: "WH-RETRY-1",
      event_type: "PAYMENT.CAPTURE.COMPLETED",
      provider: "paypal",
      valid: false,
      errors: [{ path: "legacy_key", code: "required", message: "Field is required" }],
      payload: { "id" => "WH-RETRY-1", "resource_type" => "capture", "event_type" => "PAYMENT.CAPTURE.COMPLETED" }
    )
    Hooktrace.store.save(bad_record)

    detail = mock_request.get("/events/WH-RETRY-1")
    expect(detail.body).to include("Re-validate Event")

    valid_record = Hooktrace::EventRecord.new(
      id: "WH-OK-1",
      event_type: "order.completed",
      valid: true,
      payload: { "order_id" => "ord_1" }
    )
    Hooktrace.store.save(valid_record)

    index_page = mock_request.get("/events")
    expect(index_page.body).to include("/events/WH-RETRY-1/revalidate")
    expect(index_page.body).to include("js-revalidate-form")
    expect(index_page.body).to include("revalidate-feedback")
    expect(index_page.body).not_to include("/events/WH-OK-1/revalidate")
    expect(index_page.body).not_to include("Re-validate Failed")

    Hooktrace.override("paypal.PAYMENT.CAPTURE.COMPLETED") { remove :legacy_key }

    json_res = mock_request.post(
      "/events/WH-RETRY-1/revalidate",
      "HTTP_ACCEPT" => "application/json"
    )
    expect(json_res.status).to eq(200)
    parsed = JSON.parse(json_res.body)
    expect(parsed["valid"]).to be(true)
    expect(parsed["api"]).to eq("POST /events/WH-RETRY-1/revalidate")
    expect(parsed["message"]).to include("re-validated successfully")
    expect(parsed["stats"]["passed"]).to eq(2)

    missing_json = mock_request.post(
      "/events/UNKNOWN-EVT/revalidate",
      "HTTP_ACCEPT" => "application/json"
    )
    expect(missing_json.status).to eq(404)
    expect(JSON.parse(missing_json.body)["status"]).to eq("not_found")

    Hooktrace.store.save(bad_record)

    reval_from_list = mock_request.post(
      "/events/WH-RETRY-1/revalidate",
      params: { "return_to" => "/events?status=invalid" }
    )
    expect(reval_from_list.status).to eq(302)
    expect(reval_from_list.headers["location"]).to eq("/events?status=invalid")
    expect(Hooktrace.store.find("WH-RETRY-1")).to be_valid

    Hooktrace.store.save(bad_record)
    reval = mock_request.post("/events/WH-RETRY-1/revalidate")
    expect(reval.status).to eq(302)
    expect(reval.headers["location"]).to eq("/events/WH-RETRY-1")
    expect(Hooktrace.store.find("WH-RETRY-1")).to be_valid

    Hooktrace.store.save(bad_record)
    unsafe = mock_request.post("/events/WH-RETRY-1/revalidate", params: { "return_to" => "//evil.example" })
    expect(unsafe.status).to eq(302)
    expect(unsafe.headers["location"]).to eq("/events/WH-RETRY-1")

    Hooktrace.store.save(bad_record)
    bulk = mock_request.post("/events/revalidate_failed")
    expect(bulk.status).to eq(302)
    expect(Hooktrace.store.find("WH-RETRY-1")).to be_valid
  end

  it "blocks cross-origin POST requests with 403 Forbidden" do
    res = mock_request.post("/events/clear", "HTTP_ORIGIN" => "https://malicious.example")
    expect(res.status).to eq(403)
    expect(res.body).to include("Cross-origin request blocked")
  end
end
