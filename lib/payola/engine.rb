module Payola
  class Engine < ::Rails::Engine
    isolate_namespace Payola
    engine_name 'payola'

    config.generators do |g|
      g.test_framework :rspec, fixture: false
      g.fixture_replacement :factory_bot, dir: 'spec/factories'
      g.assets false
      g.helper false
    end

    initializer :append_migrations do |app|
      unless app.root.to_s.match root.to_s
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end

    config.to_prepare do
      ::ActionController::Base.send(:helper, Payola::PriceHelper)
      ::ActionMailer::Base.send(:helper, Payola::PriceHelper)
    end

    # Configure subscription listeners after initialization to ensure classes are loaded
    config.after_initialize do
      Payola.configure do |config|
        config.subscribe 'invoice.payment_succeeded',     Payola::InvoicePaid
        config.subscribe 'invoice.payment_failed',        Payola::InvoiceFailed
        config.subscribe 'customer.subscription.updated', Payola::SyncSubscription
        config.subscribe 'customer.subscription.deleted', Payola::SubscriptionDeleted
      end
    end
  end
end
