# frozen_string_literal: true

require "tmpdir"

RSpec.describe Hooktrace::Importers::PaypalOpenApi do
  let(:notifications_spec) do
    {
      "openapi" => "3.0.3",
      "info" => { "version" => "1.11" },
      "components" => {
        "schemas" => {
          "event" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" },
              "event_version" => { "type" => "string" },
              "create_time" => { "type" => "string" },
              "resource_type" => { "type" => "string" },
              "event_type" => { "type" => "string" },
              "resource" => { "type" => "object" }
            }
          }
        }
      }
    }
  end

  let(:payments_spec) do
    {
      "openapi" => "3.0.4",
      "info" => { "version" => "2.12" },
      "components" => {
        "schemas" => {
          "date_time" => { "type" => "string" },
          "money" => {
            "type" => "object",
            "required" => %w[currency_code value],
            "properties" => {
              "currency_code" => { "type" => "string" },
              "value" => { "type" => "string" }
            }
          },
          "capture" => {
            "type" => "object",
            "allOf" => [
              {
                "type" => "object",
                "properties" => {
                  "status" => { "type" => "string" }
                }
              },
              {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" },
                  "create_time" => { "allOf" => [{ "$ref" => "#/components/schemas/date_time" }] },
                  "amount" => { "$ref" => "#/components/schemas/money" }
                }
              }
            ]
          }
        }
      }
    }
  end

  it "generates a Hooktrace contract bundle from PayPal OpenAPI specs including allOf scalars" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "notifications_webhooks_v1.json"), JSON.generate(notifications_spec))
      File.write(File.join(dir, "payments_payment_v2.json"), JSON.generate(payments_spec))
      out_path = File.join(dir, "paypal.json")

      bundle = described_class.sync(
        output_path: out_path,
        spec_base: dir,
        events: ["PAYMENT.CAPTURE.COMPLETED"],
        max_depth: 2
      )

      expect(bundle["provider"]).to eq("paypal")
      expect(bundle["api_version"]).to eq("1.11")
      expect(bundle["events"].map { |e| e["name"] }).to eq(["event.base", "PAYMENT.CAPTURE.COMPLETED"])

      capture_contract = Hooktrace::Contract.from_h(
        bundle["events"].last.merge("name" => "paypal.PAYMENT.CAPTURE.COMPLETED")
      )
      payload = {
        "id" => "WH-1",
        "event_version" => "1.0",
        "create_time" => "2026-11-11T10:00:00Z",
        "resource_type" => "capture",
        "event_type" => "PAYMENT.CAPTURE.COMPLETED",
        "resource" => {
          "id" => "CAP-1",
          "status" => "COMPLETED",
          "create_time" => "2026-11-11T10:00:00Z",
          "amount" => { "currency_code" => "USD", "value" => "57.00" }
        }
      }
      expect(capture_contract.validate(payload)).to be_valid
    end
  end
end
