# frozen_string_literal: true

require_relative "lib/hooktrace/version"

Gem::Specification.new do |spec|
  spec.name = "hooktrace"
  spec.version = Hooktrace::VERSION
  spec.authors = ["Sachin Singh Tomar"]
  spec.email = ["singh19sachin404@gmail.com"]

  spec.summary = "Webhook contract validation and schema drift detection engine"
  spec.description = "Hooktrace validates incoming Stripe, PayPal, and custom webhooks against OpenAPI " \
                     "contracts with ActiveRecord and File storage and a mountable Rack dashboard."
  spec.homepage = "https://github.com/hooktrace/hooktrace"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  # spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select { |f| File.exist?(File.expand_path(f, __dir__)) }.reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "rack", ">= 2.1", "< 4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
