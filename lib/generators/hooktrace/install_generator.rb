# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Hooktrace
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Creates the hooktrace_events migration for Hooktrace database storage."

      def copy_migration
        migration_template(
          "create_hooktrace_events.rb.erb",
          "db/migrate/create_hooktrace_events.rb",
          migration_version: migration_version
        )
      end

      private

      def migration_version
        "#{::ActiveRecord::VERSION::MAJOR}.#{::ActiveRecord::VERSION::MINOR}"
      end
    end
  end
end
