# frozen_string_literal: true

require "tempfile"
require "tmpdir"
require "hooktrace/cli"

RSpec.describe Hooktrace::CLI do
  let(:cli) { described_class.new }

  def capture_output
    orig_stdout = $stdout
    orig_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    exit_code = yield
    [exit_code, $stdout.string, $stderr.string]
  ensure
    $stdout = orig_stdout
    $stderr = orig_stderr
  end

  describe "--version and --help" do
    it "prints version and exits with 0" do
      code, out, = capture_output { cli.run(["--version"]) }
      expect(code).to eq(0)
      expect(out).to include("Hooktrace version #{Hooktrace::VERSION}")
    end

    it "prints help and exits with 0" do
      code, out, = capture_output { cli.run(["--help"]) }
      expect(code).to eq(0)
      expect(out).to include("Usage:")
    end
  end

  describe "validate" do
    it "exits with 0 when payload is valid" do
      contract = Hooktrace::Contract.define("test") do
        required :id, type: :string
      end

      Tempfile.create(["contract", ".json"]) do |c_file|
        c_file.write(contract.to_json)
        c_file.flush

        Tempfile.create(["payload", ".json"]) do |p_file|
          p_file.write(JSON.generate({ "id" => "123" }))
          p_file.flush

          code, out, = capture_output do
            cli.run(["validate", "--contract", c_file.path, "--payload", p_file.path])
          end

          expect(code).to eq(0)
          expect(out).to include("Payload is valid")
        end
      end
    end

    it "exits with 1 when payload is invalid" do
      contract = Hooktrace::Contract.define("test") do
        required :id, type: :string
      end

      Tempfile.create(["contract", ".json"]) do |c_file|
        c_file.write(contract.to_json)
        c_file.flush

        Tempfile.create(["payload", ".json"]) do |p_file|
          p_file.write(JSON.generate({ "id" => 123 }))
          p_file.flush

          code, _, err = capture_output do
            cli.run(["validate", "--contract", c_file.path, "--payload", p_file.path])
          end

          expect(code).to eq(1)
          expect(err).to include("Validation failed")
        end
      end
    end
  end

  describe "unknown command" do
    it "exits with 2 for invalid commands" do
      code, _, err = capture_output { cli.run(["bogus"]) }
      expect(code).to eq(2)
      expect(err).to include("Unknown command: bogus")
    end
  end
end
