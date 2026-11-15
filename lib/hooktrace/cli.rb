# frozen_string_literal: true

require "optparse"
require "json"
require_relative "../hooktrace"

module Hooktrace
  class CLI
    EXIT_SUCCESS = 0
    EXIT_FAILURE = 1
    EXIT_USAGE_ERROR = 2
    EXIT_RUNTIME_ERROR = 3

    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      command = argv.shift
      case command
      when "validate" then run_validate(argv)
      when "sync" then run_sync(argv)
      when "-v", "--version"
        puts "Hooktrace version #{Hooktrace::VERSION}"
        EXIT_SUCCESS
      when "-h", "--help", nil
        print_help
        command.nil? ? EXIT_USAGE_ERROR : EXIT_SUCCESS
      else
        warn "Unknown command: #{command}"
        print_help
        EXIT_USAGE_ERROR
      end
    rescue ArgumentError => e
      warn "Argument error: #{e.message}"
      EXIT_USAGE_ERROR
    rescue StandardError => e
      warn "Error: #{e.message}"
      EXIT_RUNTIME_ERROR
    end

    private

    def run_validate(argv)
      options = parse_validate_options(argv)
      contract = load_contract(options[:contract])
      payload = load_json(options[:payload])
      result = contract.validate(payload, strict: options[:strict])

      render_validate_result(result, contract, options[:json])
      result.valid? ? EXIT_SUCCESS : EXIT_FAILURE
    end

    def parse_validate_options(argv)
      options = { strict: false, json: false }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: hooktrace validate --contract <path> --payload <path> [options]"
        opts.on("-c", "--contract PATH", "Path to contract JSON file") { |v| options[:contract] = v }
        opts.on("-p", "--payload PATH", "Path to payload JSON file") { |v| options[:payload] = v }
        opts.on("-s", "--strict", "Disallow unknown fields") { options[:strict] = true }
        opts.on("-j", "--json", "Output results in JSON format") { options[:json] = true }
      end
      parser.parse!(argv)
      validate_required_options!(options, %i[contract payload], parser)
      options
    end

    def render_validate_result(result, contract, json_output)
      if json_output
        puts result.to_json
      elsif result.valid?
        puts "✓ Payload is valid according to contract '#{contract.name}'"
      else
        warn "✗ Validation failed for contract '#{contract.name}' with #{result.errors.size} error(s):"
        result.errors.each { |err| warn "  - #{err.path}: [#{err.code}] #{err.message}" }
      end
    end

    def run_sync(argv)
      options = parse_sync_options(argv)
      provider = argv.first || "all"
      result = Hooktrace.sync_contracts!(
        provider,
        output: options[:output],
        events: options[:all] ? :all : nil,
        spec_source: options[:spec]
      )
      if provider == "all"
        result.each do |name, bundle|
          puts "✓ Synced #{bundle["events"].size} contract(s) for '#{name}' (API #{bundle["api_version"]})"
        end
      else
        puts "✓ Synced #{result["events"].size} contract(s) for '#{provider}' (API #{result["api_version"]})"
      end
      EXIT_SUCCESS
    end

    def parse_sync_options(argv)
      options = { all: false }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: hooktrace sync [provider] [options]"
        opts.on("-a", "--all", "Sync all events instead of core events only") { options[:all] = true }
        opts.on("-o", "--output PATH", "Output JSON file path") { |v| options[:output] = v }
        opts.on("-s", "--spec SOURCE", "Custom OpenAPI spec URL or file path") { |v| options[:spec] = v }
      end
      parser.parse!(argv)
      options
    end

    def load_contract(path)
      Contract.from_json(File.read(path, encoding: "UTF-8"))
    end

    def load_json(path)
      JSON.parse(File.read(path, encoding: "UTF-8"))
    end

    def validate_required_options!(options, required_keys, parser)
      missing = required_keys.select { |k| options[k].nil? }
      return if missing.empty?

      warn "Missing required options: #{missing.map { |m| "--#{m}" }.join(", ")}"
      warn parser.banner
      raise ArgumentError, "Missing required options"
    end

    def print_help
      puts <<~HELP
        Hooktrace #{Hooktrace::VERSION} — Webhook contract validation & OpenAPI sync

        Usage:
          hooktrace validate --contract <path> --payload <path> [--strict] [--json]
          hooktrace sync [stripe|paypal|all] [--all] [--output PATH] [--spec URL_OR_PATH]
          hooktrace --version
          hooktrace --help
      HELP
    end
  end
end
