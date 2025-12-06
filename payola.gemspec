$:.push File.expand_path("../lib", __FILE__)

require "payola/version"

Gem::Specification.new do |s|
  s.name        = "payola-payments"
  s.version     = Payola::VERSION
  s.authors     = ["Matt Rideout"]
  s.email       = ["https://www.mattrideout.com"]
  s.homepage    = "https://github.com/mattrideout/payola"
  s.summary     = "Drop-in Rails engine for accepting payments with Stripe"
  s.description = "One-off and subscription payments for your Rails application"
  s.license     = "LGPL-3.0"

  s.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  s.add_dependency "rails", ">= 5.0"
  s.add_dependency "jquery-rails", "~> 4.6"
  s.add_dependency "stripe", "~> 13.0"
  s.add_dependency "aasm", "~> 5.5"
  s.add_dependency "stripe_event", "~> 2.13"

  s.add_development_dependency "sqlite3", "~> 2.1"
  s.add_development_dependency "rspec-rails"
  s.add_development_dependency "factory_bot_rails"
  s.add_development_dependency "stripe-ruby-mock", "~> 5.0.0"
  s.add_development_dependency "sucker_punch", ">= 2.0"
  s.add_development_dependency "ostruct"
end
