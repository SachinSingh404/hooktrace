# frozen_string_literal: true

require "tempfile"

RSpec.describe Hooktrace::Importers::StripeOpenApi do
  let(:mini_openapi) do
    {
      "openapi" => "3.0.0",
      "info" => { "version" => "2026-10-28.endive" },
      "components" => {
        "schemas" => {
          "event" => {
            "type" => "object",
            "required" => %w[id type data],
            "properties" => {
              "id" => { "type" => "string" },
              "type" => { "type" => "string" },
              "data" => { "$ref" => "#/components/schemas/notification_event_data" }
            }
          },
          "notification_event_data" => {
            "type" => "object",
            "required" => %w[object],
            "properties" => {
              "object" => { "type" => "object" }
            }
          },
          "charge" => {
            "type" => "object",
            "required" => %w[id amount customer],
            "properties" => {
              "id" => { "type" => "string" },
              "amount" => { "type" => "integer" },
              "customer" => {
                "nullable" => true,
                "anyOf" => [
                  { "type" => "string" },
                  { "$ref" => "#/components/schemas/customer" }
                ]
              },
              "tags" => {
                "type" => "array",
                "items" => { "type" => "string" }
              }
            }
          },
          "customer" => {
            "type" => "object",
            "properties" => { "id" => { "type" => "string" } }
          },
          "charge.succeeded" => {
            "type" => "object",
            "x-stripeEvent" => { "type" => "charge.succeeded" },
            "properties" => {
              "object" => { "$ref" => "#/components/schemas/charge" }
            }
          }
        }
      }
    }
  end

  it "generates a Hooktrace contract bundle from a Stripe OpenAPI spec" do
    Tempfile.create(["stripe_spec", ".json"]) do |spec_file|
      spec_file.write(JSON.generate(mini_openapi))
      spec_file.flush

      Tempfile.create(["stripe_out", ".json"]) do |out_file|
        bundle = described_class.sync(
          output_path: out_file.path,
          spec_source: spec_file.path,
          events: :all,
          max_depth: 2
        )

        expect(bundle["provider"]).to eq("stripe")
        expect(bundle["api_version"]).to eq("2026-10-28.endive")
        expect(bundle["events"].map { |e| e["name"] }).to eq(["event.base", "charge.succeeded"])

        charge_contract = Hooktrace::Contract.from_h(
          bundle["events"].last.merge("name" => "stripe.charge.succeeded")
        )
        valid_payload = {
          "id" => "evt_1",
          "type" => "charge.succeeded",
          "data" => { "object" => { "id" => "ch_1", "amount" => 1000, "customer" => "cus_1" } }
        }
        expect(charge_contract.validate(valid_payload)).to be_valid
      end
    end
  end
end
