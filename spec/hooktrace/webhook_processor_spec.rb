# frozen_string_literal: true

require "tmpdir"

RSpec.describe Hooktrace::WebhookProcessor do
  around do |example|
    original_store = Hooktrace.instance_variable_get(:@store)
    original_auto_record = Hooktrace.auto_record
    Dir.mktmpdir do |dir|
      Hooktrace.store = Hooktrace::Storage::FileStore.new(dir)
      Hooktrace.clear_registry!
      Hooktrace.load_builtin_contracts!
      example.run
    end
  ensure
    Hooktrace.clear_registry!
    Hooktrace.store = original_store
    Hooktrace.auto_record = original_auto_record
  end

  describe ".process" do
    it "auto-detects Stripe, matches base + event contract, validates, and records" do
      payload = {
        "id" => "evt_stripe_1",
        "object" => "event",
        "api_version" => "2026-10-28.endive",
        "created" => 1_793_947_906,
        "type" => "charge.succeeded",
        "livemode" => false,
        "pending_webhooks" => 1,
        "request" => { "id" => "req_1", "idempotency_key" => nil },
        "data" => {
          "object" => {
            "id" => "ch_1",
            "object" => "charge",
            "amount" => 2000,
            "amount_captured" => 2000,
            "amount_refunded" => 0,
            "application" => nil,
            "application_fee" => nil,
            "application_fee_amount" => nil,
            "balance_transaction" => nil,
            "billing_details" => {
              "address" => nil,
              "email" => nil,
              "name" => nil,
              "phone" => nil,
              "tax_id" => nil
            },
            "calculated_statement_descriptor" => "Stripe",
            "captured" => true,
            "created" => 1_793_947_906,
            "currency" => "usd",
            "customer" => nil,
            "description" => "Test payment",
            "disputed" => false,
            "failure_balance_transaction" => nil,
            "failure_code" => nil,
            "failure_message" => nil,
            "fraud_details" => {},
            "livemode" => false,
            "metadata" => {},
            "on_behalf_of" => nil,
            "outcome" => nil,
            "paid" => true,
            "payment_intent" => "pi_1",
            "payment_method" => "pm_1",
            "payment_method_details" => nil,
            "receipt_email" => nil,
            "receipt_number" => nil,
            "receipt_url" => nil,
            "refunded" => false,
            "review" => nil,
            "shipping" => nil,
            "source" => nil,
            "source_transfer" => nil,
            "statement_descriptor" => nil,
            "statement_descriptor_suffix" => nil,
            "status" => "succeeded",
            "transfer_data" => nil,
            "transfer_group" => nil
          }
        }
      }

      outcome = Hooktrace.process_webhook(payload, headers: { "HTTP_STRIPE_SIGNATURE" => "t=123,v1=abc" })

      expect(outcome).to be_valid
      expect(outcome.provider).to eq("stripe")
      expect(outcome.event_type).to eq("charge.succeeded")
      expect(outcome.event_id).to eq("evt_stripe_1")
      expect(outcome.matched_contracts).to eq(["stripe.event.base", "stripe.charge.succeeded"])

      stored = Hooktrace.store.find("evt_stripe_1")
      expect(stored).to be_valid
      expect(stored.provider).to eq("stripe")
    end

    it "falls back to stripe.event.base for Stripe events without a specific contract" do
      payload = {
        "id" => "evt_stripe_unlisted",
        "object" => "event",
        "api_version" => "2026-10-28.endive",
        "created" => 1_793_947_906,
        "type" => "custom.unlisted_event",
        "livemode" => false,
        "pending_webhooks" => 1,
        "request" => { "id" => "req_1", "idempotency_key" => nil },
        "data" => { "object" => { "id" => "obj_1" } }
      }

      outcome = Hooktrace.process_webhook(payload)

      expect(outcome).to be_valid
      expect(outcome.matched_contracts).to eq(["stripe.event.base"])
      expect(outcome.event_type).to eq("custom.unlisted_event")
    end

    it "auto-detects PayPal, matches base + specific contract, and records violations" do
      broken_paypal = {
        "id" => "WH-BROKEN-1",
        "event_version" => "1.0",
        "create_time" => "2026-11-05T07:06:23Z",
        "resource_type" => "capture",
        "event_type" => "PAYMENT.CAPTURE.COMPLETED",
        "resource" => {
          "id" => "CAP-1",
          "status" => "COMPLETED",
          "amount" => { "value" => 49.99 }
        }
      }

      outcome = Hooktrace.process_webhook(
        JSON.generate(broken_paypal),
        headers: { "PAYPAL-AUTH-ALGO" => "SHA256withRSA" }
      )

      expect(outcome).to be_invalid
      expect(outcome.provider).to eq("paypal")
      expect(outcome.event_type).to eq("PAYMENT.CAPTURE.COMPLETED")
      expect(outcome.matched_contracts).to eq(["paypal.event.base", "paypal.PAYMENT.CAPTURE.COMPLETED"])
      expect(outcome.errors).not_to be_empty

      stored = Hooktrace.store.find("WH-BROKEN-1")
      expect(stored).to be_invalid
    end

    it "records unmatched webhooks without raising" do
      outcome = Hooktrace.process_webhook({ "id" => "evt_unknown_1", "event_type" => "ping" })

      expect(outcome).to be_valid
      expect(outcome.provider).to eq("unknown")
      expect(outcome.matched_contracts).to eq([])
      expect(Hooktrace.store.find("evt_unknown_1")).to be_valid
    end

    it "raises InvalidPayloadError on malformed JSON strings" do
      expect do
        Hooktrace.process_webhook("{bad json")
      end.to raise_error(Hooktrace::InvalidPayloadError, /Invalid JSON payload/)
    end
  end
end
