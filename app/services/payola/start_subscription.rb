module Payola
  class StartSubscription
    attr_reader :subscription, :secret_key

    def self.call(subscription)
      subscription.save!
      secret_key = Payola.secret_key_for_sale(subscription)

      new(subscription, secret_key).run
    end

    def initialize(subscription, secret_key)
      @subscription = subscription
      @secret_key = secret_key
    end

    def run
      begin
        subscription.verify_charge!

        customer = find_or_create_customer

        create_params = {
          customer: customer.id,
          plan: subscription.plan.stripe_id,
          quantity: subscription.quantity,
          tax_percent: subscription.tax_percent
        }
        create_params[:trial_end] = subscription.trial_end.to_i if subscription.trial_end.present?
        create_params[:coupon] = subscription.coupon if subscription.coupon.present?
        stripe_sub = Stripe::Subscription.create(create_params, secret_key)

        # Note: As of Stripe API 2019-03-14, subscription creation may return status 'incomplete'
        # if payment processing is still pending. The subscription will transition to 'active' or
        # 'incomplete_expired' based on the payment outcome, communicated via webhooks.
        subscription.stripe_id = stripe_sub.id
        subscription.stripe_customer_id = customer.id
        subscription.sync_timestamps_from_stripe(stripe_sub)
        subscription.save!

        card_details = CardDetailsExtractor.extract(customer.sources.data.first)
        if card_details
          subscription.update(
            card_last4:      card_details[:last4],
            card_expiration: CardDetailsExtractor.expiration_date(card_details),
            card_type:       card_details[:brand]
          )
        end

        # Activate the subscription if Stripe returned 'active' or 'trialing' status
        # For 'incomplete' status (API 2019-03-14+), wait for webhook confirmation
        # before transitioning to active state
        subscription.activate! if ['active', 'trialing'].include?(stripe_sub.status)
      rescue Stripe::StripeError, RuntimeError => e
        subscription.update(error: e.message)
        subscription.fail!
      end

      subscription
    end

    def find_or_create_customer
      if subscription.stripe_customer_id.present?
        # If an existing Stripe customer id is specified, use it
        stripe_customer_id = subscription.stripe_customer_id
      elsif subscription.owner
        # Look for an existing successful Subscription for the same owner, and use its Stripe customer id
        stripe_customer_id = Subscription.where(owner: subscription.owner).where("stripe_customer_id IS NOT NULL").where("state in ('active', 'canceled')").pluck(:stripe_customer_id).first
      end

      if stripe_customer_id
        # Retrieve the customer from Stripe and use it for this subscription
        customer = Stripe::Customer.retrieve(stripe_customer_id, secret_key)

        unless customer.try(:deleted)
          if subscription.stripe_token.present?
            Stripe::Customer.update(
              customer.id,
              { source: subscription.stripe_token },
              secret_key
            )
            customer = Stripe::Customer.retrieve(stripe_customer_id, secret_key)
          end

          return customer
        end
      end

      if subscription.plan.amount > 0 and not subscription.stripe_token.present?
        raise "stripeToken required for new customer with paid subscription"
      end

      customer_create_params = {
        source: subscription.stripe_token,
        email:  subscription.email
      }

      customer = Stripe::Customer.create(customer_create_params, secret_key)

      if subscription.setup_fee.present?
        plan = subscription.plan
        description = plan.try(:setup_fee_description, subscription) || 'Setup Fee'
        Stripe::InvoiceItem.create({
          customer: customer.id,
          amount: subscription.setup_fee,
          currency: subscription.currency,
          description: description
        }, secret_key)
      end

      customer
    end
  end

end
