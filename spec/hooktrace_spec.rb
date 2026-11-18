# frozen_string_literal: true

require "tmpdir"

RSpec.describe Hooktrace do
  around do |example|
    original_store = described_class.instance_variable_get(:@store)
    original_auto_record = described_class.auto_record
    Dir.mktmpdir do |dir|
      described_class.store = Hooktrace::Storage::FileStore.new(dir)
      described_class.clear_registry!
      example.run
    end
  ensure
    described_class.clear_registry!
    described_class.store = original_store
    described_class.auto_record = original_auto_record
  end

  it "has a version number" do
    expect(Hooktrace::VERSION).not_to be_nil
  end

  it "defines and retrieves contracts via the registry" do
    contract = described_class.define("user.created") do
      required :user_id, type: :string
    end

    expect(described_class["user.created"]).to eq(contract)
    expect(described_class.contract("user.created")).to eq(contract)
  end

  it "raises ContractNotFoundError when accessing an undefined contract" do
    expect do
      described_class["non_existent"]
    end.to raise_error(Hooktrace::ContractNotFoundError, /Contract 'non_existent' is not defined/)
  end

  it "validates using the top-level validate method" do
    described_class.define("invoice.paid") do
      required :invoice_id, type: :string
    end

    valid_result = described_class.validate("invoice.paid", { "invoice_id" => "inv_1" })
    expect(valid_result).to be_valid

    invalid_result = described_class.validate("invoice.paid", {})
    expect(invalid_result).not_to be_valid
  end

  it "aliases HookTrace to Hooktrace" do
    expect(HookTrace).to eq(Hooktrace)
  end

  it "loads a contract from a JSON file and registers it" do
    contract = described_class.load_contract(
      File.expand_path("../lib/hooktrace/contracts/stripe.json", __dir__)
    )

    expect(contract).not_to be_empty
    expect(described_class["stripe.charge.failed"]).not_to be_nil
  end

  it "loads all contracts from a directory" do
    contracts = described_class.load_contracts_from(
      File.expand_path("../lib/hooktrace/contracts", __dir__)
    )

    expect(contracts.size).to be >= 2
    expect(described_class["stripe.event.base"]).not_to be_nil
    expect(described_class["paypal.event.base"]).not_to be_nil
  end

  it "loads multiple events from a single provider bundle JSON file" do
    bundle_json = JSON.generate({
                                  "provider" => "stripe",
                                  "events" => [
                                    {
                                      "name" => "payment_intent.succeeded",
                                      "fields" => [{ "name" => "id", "type" => "string", "required" => true }]
                                    },
                                    {
                                      "name" => "charge.succeeded",
                                      "fields" => [{ "name" => "amount", "type" => "integer", "required" => true }]
                                    }
                                  ]
                                })

    Tempfile.create(["stripe_bundle", ".json"]) do |f|
      f.write(bundle_json)
      f.flush

      contracts = described_class.load_contract(f.path)
      expect(contracts.size).to eq(2)
      expect(described_class["stripe.payment_intent.succeeded"]).not_to be_nil
      expect(described_class["stripe.charge.succeeded"]).not_to be_nil
    end
  end

  it "lists builtin providers and loads builtin contracts" do
    expect(described_class.builtin_providers).to include("paypal", "stripe")

    contracts = described_class.load_builtin_contracts!(:stripe)
    expect(contracts.size).to be >= 1
    expect(described_class["stripe.payment_intent.succeeded"]).not_to be_nil

    all_contracts = described_class.load_builtin_contracts!
    expect(all_contracts.size).to be > contracts.size
    expect(described_class["paypal.PAYMENT.CAPTURE.COMPLETED"]).not_to be_nil
  end

  it "automatically loads builtin contracts on-demand when accessed by name" do
    described_class.clear_registry!
    expect(described_class.registry).to be_empty

    contract = described_class["stripe.payment_intent.succeeded"]
    expect(contract).not_to be_nil
    expect(contract.name).to eq("stripe.payment_intent.succeeded")
  end

  it "automatically records valid and invalid validation outcomes to store" do
    described_class.define("stripe.charge.succeeded") do
      required :id, type: :string
    end

    valid_res = described_class.validate("stripe.charge.succeeded", { "id" => "evt_ok" })
    invalid_res = described_class.validate("stripe.charge.succeeded", {}, id: "evt_bad")

    expect(valid_res).to be_valid
    expect(invalid_res).not_to be_valid
    expect(described_class.store.count).to eq(2)

    ok_rec = described_class.store.find("evt_ok")
    expect(ok_rec).to be_valid
    expect(ok_rec.errors).to be_empty

    bad_rec = described_class.store.find("evt_bad")
    expect(bad_rec).to be_invalid
    expect(bad_rec.errors.size).to eq(1)
  end

  it "validates an array of contracts and records a single merged event" do
    described_class.define("stripe.event.base") do
      required :id, type: :string
    end
    described_class.define("stripe.charge.succeeded") do
      required :amount, type: :integer
    end

    result = described_class.validate(["stripe.event.base", "stripe.charge.succeeded"], { "id" => "evt_multi" })
    expect(result).not_to be_valid
    expect(described_class.store.count).to eq(1)

    rec = described_class.store.find("evt_multi")
    expect(rec.event_type).to eq("stripe.charge.succeeded")
    expect(rec.errors.size).to eq(1)
  end

  it "skips saving when record: false or auto_record is false" do
    described_class.define("order.paid") do
      required :id, type: :string
    end

    described_class.validate("order.paid", { "id" => "1" }, record: false)
    described_class.auto_record = false
    described_class.validate("order.paid", { "id" => "2" })

    expect(described_class.store.count).to eq(0)
  end

  it "supports Hooktrace.configure and Hooktrace.override in initializers" do
    described_class.configure do |config|
      config.override("stripe.charge.succeeded") do
        object :data do
          object :object do
            optional :custom_app_tag, type: :string
            remove :statement_descriptor_suffix
          end
        end
      end
    end

    contract = described_class["stripe.charge.succeeded"]
    obj_fields = contract.fields.find { |f| f.name == "data" }.fields.first.fields
    expect(obj_fields.map(&:name)).to include("custom_app_tag", "amount")
    expect(obj_fields.map(&:name)).not_to include("statement_descriptor_suffix")
  end

  it "revalidates stored invalid events in place via revalidate and revalidate_failed" do
    described_class.define("stripe.custom.order") do
      required :id, type: :string
      required :notes, type: :string
    end

    outcome = described_class.process_webhook({ "id" => "evt_fix_1", "object" => "event", "type" => "custom.order" })
    expect(outcome).to be_invalid
    expect(described_class.store.count).to eq(1)

    described_class.override("stripe.custom.order") { remove :notes }

    summary = described_class.revalidate_failed
    expect(summary).to eq({ total: 1, passed: 1, still_failed: 0 })
    expect(described_class.store.count).to eq(1)
    expect(described_class.store.find("evt_fix_1")).to be_valid
  end
end
