# Hooktrace

**Webhook contract validation, OpenAPI schema sync, and live event diagnostics for Ruby & Rails applications.**

Third-party webhook providers (**Stripe** and **PayPal**) evolve their webhook payloads across API versions. Hooktrace ships pre-synced OpenAPI schemas, automatically matches and validates real incoming webhooks, records validation results into your database, and provides a Sidekiq-style dashboard for inspecting payload violations.

---

## Features

- **Built-In OpenAPI Contracts (Stripe & PayPal):** Ships with 32 core Stripe contracts (`2026-10-28.endive`) and 21 PayPal contracts (`v1.11`) generated directly from official OpenAPI specifications and auto-loaded on boot.
- **Automatic Real Webhook Matching:** `Hooktrace.process_webhook` auto-detects Stripe or PayPal from headers/payload, matches `<provider>.event.base` + `<provider>.<event_type>`, and validates in one call.
- **Automatic Database Persistence:** `Hooktrace::Storage::ActiveRecordStore` automatically persists valid and failed webhook events to the `hooktrace_events` table whenever you validate (with `FileStore` fallback outside Rails).
- **Initializer Override DSL:** Customize, add, or remove fields on any built-in OpenAPI contract inside `config/initializers/hooktrace.rb` using `Hooktrace.configure` and `config.override`.
- **OpenAPI CLI Sync:** Refresh contracts directly from Stripe and PayPal OpenAPI repositories anytime with `hooktrace sync`.
- **Mountable Web Dashboard:** Sidekiq-style Rack UI (`Hooktrace::Web`) for browsing captured events, contract violations, and active contracts.
- **Zero Heavy Dependencies:** Core & OpenAPI sync use Ruby stdlib (`json`, `net/http`, `erb`, `optparse`), and the Web UI only requires `rack >= 2.1` (`ActiveRecord` is optional).

---

## Quick Start (How to Use in Your Rails App)

### 1. Install the Gem

Add to your `Gemfile`:

```ruby
gem "hooktrace"
```

Run:

```bash
bundle install
```

### 2. Create the Database Table

Generate and run the `hooktrace_events` migration:

```bash
rails generate hooktrace:install
rails db:migrate
```

Once `hooktrace_events` exists, `Hooktrace.store` automatically selects `Hooktrace::Storage::ActiveRecordStore`.

### 3. Mount the Dashboard (`config/routes.rb`)

```ruby
Rails.application.routes.draw do
  mount Hooktrace::Web => "/hooktrace"
end
```

### 4. Validate Incoming Real Webhooks in Your Controller

Pass the raw request body (or parsed Hash) and headers to `Hooktrace.process_webhook`. Validation and database recording happen automatically—no manual `store.save` needed:

```ruby
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    event = Stripe::Webhook.construct_event(
      request.raw_post,
      request.env["HTTP_STRIPE_SIGNATURE"],
      ENV["STRIPE_WEBHOOK_SECRET"]
    )
    payload = JSON.parse(event.to_json)

    outcome = Hooktrace.process_webhook(payload, headers: request.headers.to_h, provider: "stripe")
    render json: outcome.to_h, status: outcome.valid? ? :ok : :unprocessable_entity
  end

  def paypal
    outcome = Hooktrace.process_webhook(request.raw_post, headers: request.headers.to_h, provider: "paypal")
    render json: outcome.to_h, status: :ok
  rescue Hooktrace::InvalidPayloadError => e
    render json: { error: e.message }, status: :bad_request
  end
end
```

You can also validate against specific contract name(s) directly:

```ruby
# Validates & auto-saves one event record into hooktrace_events
result = Hooktrace.validate(["stripe.event.base", "stripe.charge.succeeded"], payload)

result.valid? # => true / false
result.errors # => Array<Hooktrace::Error>
```

*(Pass `record: false` or set `Hooktrace.auto_record = false` to skip persistence.)*

Open **`http://localhost:3000/hooktrace`** to view live stats, captured payloads, violation details, and active contracts.

---

## Overriding Contracts in `config/initializers/hooktrace.rb`

You do **not** need an initializer for default behavior, because built-in contracts and `ActiveRecordStore` configure themselves automatically.

If your app needs custom rules on top of a built-in OpenAPI contract, add `config/initializers/hooktrace.rb`:

```ruby
require "hooktrace"

Hooktrace.configure do |config|
  # Partially override a built-in OpenAPI contract
  config.override("stripe.charge.succeeded") do
    object :data do
      object :object do
        required :customer, type: :string, nullable: false # tighten existing field
        optional :tenant_id, type: :string                 # add app-specific field
        remove :statement_descriptor_suffix                # ignore an unneeded field
      end
    end
  end

  # Or define a brand-new custom contract
  config.define("custom.order.created") do
    required :id, type: :string
    required :amount, type: :integer
  end

  # Or load custom JSON bundles from a folder
  # config.contracts_path = Rails.root.join("config", "contracts")
end
```

---

## Syncing Updated OpenAPI Contracts

When Stripe or PayPal updates their webhook schemas, refresh your contracts using the CLI or Ruby API:

```bash
# Sync core Stripe & PayPal contracts into lib/hooktrace/contracts/
hooktrace sync all

# Sync only Stripe (use --all for all 275+ Stripe events)
hooktrace sync stripe
hooktrace sync stripe --all --output config/contracts/stripe.json

# Sync only PayPal
hooktrace sync paypal --output config/contracts/paypal.json
```

Or in Ruby:

```ruby
Hooktrace.sync_contracts!(:stripe, output: Rails.root.join("config/contracts/stripe.json"))
Hooktrace.sync_contracts!(:paypal, output: Rails.root.join("config/contracts/paypal.json"))
```

### Validate a Payload via CLI

```bash
hooktrace validate --contract path/to/contract.json --payload path/to/payload.json
```

Exit codes: `0` (valid / success), `1` (validation failure), `2` (invalid arguments), `3` (runtime error).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history. Highlights of recent additions:

- **OpenAPI Importers (`StripeOpenApi`, `PaypalOpenApi`):** Auto-sync built-in contracts from official Stripe & PayPal OpenAPI specs via `hooktrace sync`.
- **Automatic Webhook Matching (`Hooktrace.process_webhook`):** Auto-detect Stripe/PayPal webhooks, match base + event contracts, validate, and record in one call.
- **Database Persistence (`ActiveRecordStore`):** Added `rails generate hooktrace:install` for the `hooktrace_events` table with auto-detection.
- **Initializer Override DSL:** Added `Hooktrace.configure` and `Hooktrace.override` to customize built-in schemas per app.
- **ERB Web Dashboard:** Refactored `Hooktrace::Web` HTML and CSS into modular templates under `lib/hooktrace/web/`.

---

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
