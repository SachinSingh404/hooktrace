# frozen_string_literal: true

require "json"
require "set"
require_relative "open_api_schema_converter"

module Hooktrace
  module Importers
    class PaypalOpenApi
      DEFAULT_SPEC_BASE = "https://raw.githubusercontent.com/paypal/paypal-rest-api-specifications/main/openapi"
      DEFAULT_MAX_DEPTH = 2
      ENVELOPE_REQUIRED = %w[id event_version create_time resource_type event_type resource].freeze

      EVENT_RESOURCE_MAP = {
        "PAYMENT.CAPTURE.COMPLETED" => ["payments_payment_v2.json", "capture"],
        "PAYMENT.CAPTURE.DENIED" => ["payments_payment_v2.json", "capture"],
        "PAYMENT.CAPTURE.PENDING" => ["payments_payment_v2.json", "capture"],
        "PAYMENT.CAPTURE.REFUNDED" => ["payments_payment_v2.json", "refund"],
        "PAYMENT.AUTHORIZATION.CREATED" => ["payments_payment_v2.json", "authorization"],
        "PAYMENT.AUTHORIZATION.VOIDED" => ["payments_payment_v2.json", "authorization"],
        "CHECKOUT.ORDER.APPROVED" => ["checkout_orders_v2.json", "order"],
        "CHECKOUT.ORDER.COMPLETED" => ["checkout_orders_v2.json", "order"],
        "CHECKOUT.ORDER.SAVED" => ["checkout_orders_v2.json", "order"],
        "BILLING.SUBSCRIPTION.ACTIVATED" => ["billing_subscriptions_v1.json", "subscription"],
        "BILLING.SUBSCRIPTION.CANCELLED" => ["billing_subscriptions_v1.json", "subscription"],
        "BILLING.SUBSCRIPTION.CREATED" => ["billing_subscriptions_v1.json", "subscription"],
        "BILLING.SUBSCRIPTION.SUSPENDED" => ["billing_subscriptions_v1.json", "subscription"],
        "BILLING.SUBSCRIPTION.UPDATED" => ["billing_subscriptions_v1.json", "subscription"],
        "INVOICING.INVOICE.CANCELLED" => ["invoicing_v2.json", "invoice"],
        "INVOICING.INVOICE.CREATED" => ["invoicing_v2.json", "invoice"],
        "INVOICING.INVOICE.PAID" => ["invoicing_v2.json", "invoice"],
        "CUSTOMER.DISPUTE.CREATED" => ["customer_disputes_v1.json", "dispute"],
        "CUSTOMER.DISPUTE.RESOLVED" => ["customer_disputes_v1.json", "dispute"],
        "CUSTOMER.DISPUTE.UPDATED" => ["customer_disputes_v1.json", "dispute"]
      }.freeze

      def self.sync(output_path:, spec_base: DEFAULT_SPEC_BASE, events: nil, max_depth: DEFAULT_MAX_DEPTH)
        new(spec_base: spec_base, events: events, max_depth: max_depth).sync(output_path: output_path)
      end

      def initialize(spec_base: DEFAULT_SPEC_BASE, events: nil, max_depth: DEFAULT_MAX_DEPTH)
        @spec_base = spec_base.to_s.sub(%r{/+\z}, "")
        @events = events
        @converter = OpenApiSchemaConverter.new(max_depth: max_depth)
        @spec_cache = {}
      end

      def generate_bundle
        webhooks_spec = load_spec_file("notifications_webhooks_v1.json")
        webhooks_schemas = webhooks_spec.fetch("components", {}).fetch("schemas", {})
        event_schema = webhooks_schemas.fetch("event") do
          raise Hooktrace::StandardError, "Missing 'event' schema in PayPal notifications_webhooks_v1.json"
        end

        base_fields = @converter.build_fields(
          event_schema, webhooks_schemas,
          depth: 0, visited: Set.new(["event"]), extra_required: ENVELOPE_REQUIRED
        )
        event_entries = [{ "name" => "event.base", "fields" => base_fields }]

        selected_events.each do |event_name, (file_name, schema_name)|
          event_entries << build_event_entry(event_name, base_fields, file_name, schema_name)
        end

        {
          "provider" => "paypal",
          "api_version" => webhooks_spec.dig("info", "version"),
          "events" => event_entries
        }
      end

      def sync(output_path:)
        bundle = generate_bundle
        File.write(output_path, "#{JSON.pretty_generate(bundle)}\n", encoding: "UTF-8")
        bundle
      end

      private

      def selected_events
        return EVENT_RESOURCE_MAP.sort_by(&:first) if @events.nil? || @events == :all

        allow = @events.map(&:to_s)
        EVENT_RESOURCE_MAP.slice(*allow).sort_by(&:first)
      end

      def build_event_entry(event_name, base_fields, file_name, schema_name)
        spec = load_spec_file(file_name)
        schemas = spec.fetch("components", {}).fetch("schemas", {})
        resource_schema = schemas[schema_name]

        resource_fields = if resource_schema
                            @converter.build_fields(
                              resource_schema, schemas,
                              depth: 1, visited: Set.new([schema_name]), extra_required: ["id"]
                            )
                          else
                            []
                          end

        fields = base_fields.map do |field|
          field["name"] == "resource" ? field.merge("fields" => resource_fields) : field
        end

        { "name" => event_name, "fields" => fields }
      end

      def load_spec_file(file_name)
        @spec_cache[file_name] ||= OpenApiSchemaConverter.load_spec("#{@spec_base}/#{file_name}")
      end
    end
  end
end
