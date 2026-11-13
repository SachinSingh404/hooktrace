# frozen_string_literal: true

require "json"
require "set"
require_relative "open_api_schema_converter"

module Hooktrace
  module Importers
    class StripeOpenApi
      DEFAULT_SPEC_URL = "https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.sdk.json"
      DEFAULT_MAX_DEPTH = 2

      CORE_EVENTS = %w[
        charge.captured
        charge.dispute.created
        charge.failed
        charge.refunded
        charge.succeeded
        charge.updated
        checkout.session.completed
        checkout.session.expired
        customer.created
        customer.deleted
        customer.subscription.created
        customer.subscription.deleted
        customer.subscription.updated
        customer.updated
        invoice.created
        invoice.finalized
        invoice.paid
        invoice.payment_failed
        payment_intent.canceled
        payment_intent.created
        payment_intent.payment_failed
        payment_intent.processing
        payment_intent.requires_action
        payment_intent.succeeded
        payment_method.attached
        payment_method.detached
        payout.created
        payout.failed
        payout.paid
        refund.created
        refund.failed
      ].freeze

      def self.sync(output_path:, spec_source: DEFAULT_SPEC_URL, events: CORE_EVENTS, max_depth: DEFAULT_MAX_DEPTH)
        new(spec_source: spec_source, events: events, max_depth: max_depth).sync(output_path: output_path)
      end

      def initialize(spec_source: DEFAULT_SPEC_URL, events: CORE_EVENTS, max_depth: DEFAULT_MAX_DEPTH)
        @spec_source = spec_source
        @events = events
        @converter = OpenApiSchemaConverter.new(max_depth: max_depth)
      end

      def generate_bundle
        spec = OpenApiSchemaConverter.load_spec(@spec_source)
        schemas = spec.fetch("components", {}).fetch("schemas", {})
        event_schema = schemas.fetch("event") do
          raise Hooktrace::StandardError, "Missing 'event' schema in Stripe OpenAPI spec"
        end

        base_fields = @converter.build_fields(event_schema, schemas, depth: 0, visited: Set.new(["event"]))
        event_entries = [{ "name" => "event.base", "fields" => base_fields }]

        select_event_schemas(schemas).each do |event_name, schema|
          object_ref = schema.dig("properties", "data", "properties", "object") || schema.dig("properties", "object")
          event_fields = build_event_fields(base_fields, object_ref, schemas)
          event_entries << { "name" => event_name, "fields" => event_fields }
        end

        {
          "provider" => "stripe",
          "api_version" => spec.dig("info", "version"),
          "events" => event_entries
        }
      end

      def sync(output_path:)
        bundle = generate_bundle
        File.write(output_path, "#{JSON.pretty_generate(bundle)}\n", encoding: "UTF-8")
        bundle
      end

      private

      def select_event_schemas(schemas)
        all_events = schemas.select { |_, s| s.is_a?(Hash) && s.key?("x-stripeEvent") }
        filtered = if @events == :all || @events.nil?
                     all_events
                   else
                     allow = @events.map(&:to_s)
                     all_events.slice(*allow)
                   end
        filtered.sort_by(&:first)
      end

      def build_event_fields(base_fields, object_schema_ref, schemas)
        object_fields = if object_schema_ref
                          @converter.build_fields(object_schema_ref, schemas, depth: 1, visited: Set.new)
                        else
                          []
                        end

        base_fields.map do |field|
          next field unless field["name"] == "data"

          updated_data_children = (field["fields"] || []).map do |child|
            child["name"] == "object" ? child.merge("fields" => object_fields) : child
          end

          field.merge("fields" => updated_data_children)
        end
      end
    end
  end
end
