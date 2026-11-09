# frozen_string_literal: true

require_relative "lib/hooktrace/version"

Gem::Specification.new do |spec|
  spec.name = "hooktrace"
  spec.version = Hooktrace::VERSION
  spec.authors = ["Sachin Singh Tomar"]
  spec.email = ["singh19sachin404@gmail.com"]

  spec.summary = "Webhook payload schema contracts and runtime monitoring for Rails"
  spec.description = "Hooktrace provides contract-driven validation, drift detection, and observability for incoming webhook payloads."
  spec.homepage = "https://github.com/SachinSingh404/hooktrace"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", ">= 2.0"
end
