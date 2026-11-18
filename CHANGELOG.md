# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Built-in OpenAPI Provider Contracts & Sync Importers:**
  - `Hooktrace::Importers::OpenApiSchemaConverter` to convert OpenAPI 3 schemas (`$ref`, `allOf`, `anyOf`/`oneOf`, `required`, `nullable`, arrays, and nested objects) into Hooktrace contracts.
  - `Hooktrace::Importers::StripeOpenApi` (`spec3.sdk.json`) generating 32 core Stripe contracts (`event.base` + `charge.*`, `payment_intent.*`, `checkout.session.*`, `invoice.*`, `customer.*`, `payment_method.*`, `payout.*`, `refund.*`), with `--all` support for 275+ Stripe events.
  - `Hooktrace::Importers::PaypalOpenApi` (`notifications_webhooks_v1.json` + Payments, Orders, Subscriptions, Invoicing, and Disputes specs) generating 21 PayPal contracts.
  - Pre-synced `lib/hooktrace/contracts/stripe.json` and `lib/hooktrace/contracts/paypal.json` auto-loaded on boot (`Hooktrace.load_builtin_contracts!`, `Hooktrace.builtin_providers`).
  - `Hooktrace.sync_contracts!` Ruby API and `hooktrace sync [stripe|paypal|all]` CLI command.
- **Automatic Real Webhook Processing:**
  - `Hooktrace::WebhookProcessor` (`Hooktrace.process_webhook` / `Hooktrace.handle_webhook`) and `Hooktrace::WebhookOutcome` to parse raw JSON or Hash payloads, auto-detect Stripe and PayPal from headers/payload, match `<provider>.event.base` + `<provider>.<event_type>`, validate, and persist results.
- **Database Storage & Rails Install Generator:**
  - `Hooktrace::Storage::ActiveRecordStore` storing validation records and errors in `hooktrace_events` (auto-selected when ActiveRecord is connected and the table exists, keeping `ActiveRecord` an optional dependency with `FileStore` fallback).
  - `Hooktrace::Generators::InstallGenerator` (`rails generate hooktrace:install`) to generate the `CreateHooktraceEvents` migration.
- **Contract Overrides & Configuration DSL:**
  - `Hooktrace.configure`, `Hooktrace.override`, `Hooktrace.contracts_path=`, and `Hooktrace::Contract.override` (`required`, `optional`, `object`, `array`, `remove`) to customize built-in contracts in Rails initializers.

### Changed
- Updated `Hooktrace.validate` to accept single or multiple contracts, deduplicate overlapping errors, and auto-save validation outcomes to `Hooktrace.store` when `auto_record` is enabled.
- Refactored `Hooktrace::Web` to render external ERB templates (`lib/hooktrace/web/views/*.erb`) and `lib/hooktrace/web/assets/application.css` instead of inline HTML heredocs.
- Simplified `Hooktrace::EventRecord` and `Hooktrace::Contract` deserialization (`transform_keys(&:to_s)`) and focused provider detection strictly on Stripe and PayPal.

### Removed
- Removed unused/superseded modules and sample files (`examples/`, `Inferrer`, `Comparator`, `FixtureLoader`, RSpec matcher adapter, and Shopify fixtures).

## [0.1.0] - 2026-10-30

### Added
- Core contract DSL (`Hooktrace::Contract`, `Hooktrace::Field`), schema validator (`Hooktrace::Validator`), and immutable result/error models (`Hooktrace::Result`, `Hooktrace::Error`).
- JSON contract loading (`Hooktrace.load_contract`, `Hooktrace.load_contracts_from`) with multi-event provider bundle support.
- Event recording (`Hooktrace::EventRecord`, `Hooktrace::Storage::FileStore`) and mountable Rack dashboard (`Hooktrace::Web`).
- Standalone CLI executable (`exe/hooktrace`) for contract validation.
