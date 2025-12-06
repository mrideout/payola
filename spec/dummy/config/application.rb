require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)
require "payola"

module Dummy
  class Application < Rails::Application
    # Initialize configuration defaults for Rails 8.1
    config.load_defaults 8.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    config.i18n.available_locales = [:en, :de]

    # Configure secret_key_base for test environment
    # For development and production, set SECRET_KEY_BASE environment variable
    if Rails.env.test?
      config.secret_key_base = SecureRandom.hex(64)
    end
  end
end
