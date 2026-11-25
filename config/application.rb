require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module SimpleDrive
  class Application < Rails::Application
    config.load_defaults 7.2
    config.autoload_lib(ignore: %w[tasks])

    config.api_only = true
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Storage backend settings (see config/simple_drive.yml)
    config.x.simple_drive = config_for(:simple_drive)
  end
end
