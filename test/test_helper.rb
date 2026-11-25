ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "base64"
require "tmpdir"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)

    setup do
      Storage.reset!
      FileUtils.rm_rf(Rails.configuration.x.simple_drive[:local][:root])
    end
  end
end

module AuthHelpers
  def auth_headers(raw_token = @raw_token)
    { "Authorization" => "Bearer #{raw_token}", "Content-Type" => "application/json" }
  end
end
