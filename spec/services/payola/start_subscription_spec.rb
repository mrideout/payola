require 'spec_helper'

module Payola
  describe StartSubscription do
    let(:stripe_helper) { StripeMock.create_test_helper }
    let(:token){ StripeMock.generate_card_token({}) }
    let(:user){ User.create }

    describe "#call" do
      it "should create a customer" do
        plan = create(:subscription_plan)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token)
        StartSubscription.call(subscription)
        expect(subscription.reload.stripe_customer_id).to_not be_nil
      end
      it "should create a customer with free plan without stripe_token" do
        plan = create(:subscription_plan, amount:0)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: nil)
        StartSubscription.call(subscription)
        expect(subscription.reload.stripe_customer_id).to_not be_nil
      end
      it "should capture credit card info" do
        plan = create(:subscription_plan)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token)
        StartSubscription.call(subscription)
        expect(subscription.reload.stripe_id).to_not be_nil
        expect(subscription.reload.card_last4).to_not be_nil
        expect(subscription.reload.card_expiration).to_not be_nil
        expect(subscription.reload.card_type).to_not be_nil
      end
      describe "on error" do
        it "should update the error attribute" do
          StripeMock.prepare_card_error(:card_declined, :new_customer)
          plan = create(:subscription_plan)
          subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token)
          StartSubscription.call(subscription)
          expect(subscription.reload.error).to_not be_nil
          expect(subscription.errored?).to be true
        end
      end

      it "should re-use an explicitly specified customer" do
        plan = create(:subscription_plan)
        stripe_customer = Stripe::Customer.create
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: nil, stripe_customer_id: stripe_customer.id)
        expect(Stripe::Customer).to_not receive(:create)
        StartSubscription.call(subscription)
      end

      it "should fail if the explicitly specified customer has been deleted" do
        plan = create(:subscription_plan)
        stripe_customer = Stripe::Customer.create
        stripe_customer.delete
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: nil, stripe_customer_id: stripe_customer.id)
        expect(subscription).to receive(:fail!)
        StartSubscription.call(subscription)
        expect(subscription.reload.error).to eq "stripeToken required for new customer with paid subscription"
      end

      it "should re-use an existing customer" do
        plan = create(:subscription_plan)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token, owner: user)
        StartSubscription.call(subscription)
        CancelSubscription.call(subscription)

        subscription2 = create(:subscription, state: 'processing', plan: plan, stripe_token: nil, owner: user)
        StartSubscription.call(subscription2)
        expect(subscription2.reload.stripe_customer_id).to_not be_nil
        expect(subscription2.reload.stripe_customer_id).to eq subscription.reload.stripe_customer_id
      end

      it "should assign a passed payment source to an existing customer without one" do
        plan = create(:subscription_plan, amount:0)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: nil, owner: user)
        StartSubscription.call(subscription)
        expect(Stripe::Customer.retrieve(subscription.reload.stripe_customer_id).default_source).to be_nil

        plan2 = create(:subscription_plan)
        subscription2 = create(:subscription, state: 'processing', plan: plan2, stripe_token: token, owner: user)
        StartSubscription.call(subscription2)

        stripe_customer_id = subscription2.reload.stripe_customer_id
        expect(stripe_customer_id).to eq subscription.reload.stripe_customer_id
        expect(Stripe::Customer.retrieve(stripe_customer_id).default_source).to_not be_nil
      end

      it "should update payment source when existing customer with a card provides a new token" do
        plan = create(:subscription_plan)

        # First subscription creates customer with a card
        subscription1 = create(:subscription, state: 'processing', plan: plan, stripe_token: token, owner: user)
        StartSubscription.call(subscription1)
        CancelSubscription.call(subscription1)

        original_source = Stripe::Customer.retrieve(subscription1.reload.stripe_customer_id).default_source
        expect(original_source).to_not be_nil

        # Second subscription with a NEW token should update the payment source
        new_token = StripeMock.generate_card_token({})
        subscription2 = create(:subscription, state: 'processing', plan: plan, stripe_token: new_token, owner: user)
        StartSubscription.call(subscription2)

        updated_source = Stripe::Customer.retrieve(subscription2.reload.stripe_customer_id).default_source
        expect(updated_source).to_not be_nil
        expect(updated_source).to_not eq original_source
      end

      it "should not re-use an existing customer that has been deleted" do
        plan = create(:subscription_plan)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token, owner: user)
        StartSubscription.call(subscription)
        deleted_customer_id = subscription.reload.stripe_customer_id
        Stripe::Customer.retrieve(deleted_customer_id).delete

        subscription2 = create(:subscription, state: 'processing', plan: plan, stripe_token: nil, owner: user)
        expect(subscription2).to receive(:fail!)
        StartSubscription.call(subscription2)
        expect(subscription2.reload.error).to eq "stripeToken required for new customer with paid subscription"
      end

      it "should create an invoice item with a setup fee" do
        plan = create(:subscription_plan)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token, owner: user, setup_fee: 100)
        StartSubscription.call(subscription)

        ii = Stripe::InvoiceItem.list(customer: subscription.stripe_customer_id).first
        expect(ii).to_not be_nil
        expect(ii.amount).to eq 100
        expect(ii.description).to eq "Setup Fee"
      end

      it "should allow the plan to override the setup fee description" do
        plan = create(:subscription_plan)
        subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token, owner: user, setup_fee: 100)

        expect(plan).to receive(:setup_fee_description).with(subscription).and_return('Random Mystery Fee')
        StartSubscription.call(subscription)

        ii = Stripe::InvoiceItem.list(customer: subscription.stripe_customer_id).first
        expect(ii).to_not be_nil
        expect(ii.amount).to eq 100
        expect(ii.description).to eq 'Random Mystery Fee'
      end

      describe "subscription activation based on Stripe status (API 2019-03-14+)" do
        let(:plan) { create(:subscription_plan) }

        # Helper method to create a mock Stripe subscription with specified status
        def mock_stripe_subscription(status, plan_amount)
          base_attrs = {
            id: 'sub_test123',
            status: status,
            customer: 'cus_test123',
            current_period_start: Time.now.to_i,
            current_period_end: (Time.now + 30.days).to_i,
            ended_at: nil,
            canceled_at: nil,
            quantity: 1,
            cancel_at_period_end: false,
            plan: double('Plan', amount: plan_amount, currency: 'usd')
          }

          # Add trial fields for trialing status
          if status == 'trialing'
            base_attrs[:trial_start] = Time.now.to_i
            base_attrs[:trial_end] = (Time.now + 14.days).to_i
          else
            base_attrs[:trial_start] = nil
            base_attrs[:trial_end] = nil
          end

          double('Stripe::Subscription', base_attrs)
        end

        it "should activate subscription when Stripe returns 'active' status" do
          subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token)

          allow(Stripe::Subscription).to receive(:create).and_return(
            mock_stripe_subscription('active', plan.amount)
          )

          StartSubscription.call(subscription)

          expect(subscription.reload.active?).to be true
          expect(subscription.reload.stripe_status).to eq 'active'
        end

        it "should activate subscription when Stripe returns 'trialing' status" do
          subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token)

          allow(Stripe::Subscription).to receive(:create).and_return(
            mock_stripe_subscription('trialing', plan.amount)
          )

          StartSubscription.call(subscription)

          expect(subscription.reload.active?).to be true
          expect(subscription.reload.stripe_status).to eq 'trialing'
        end

        it "should NOT activate subscription when Stripe returns 'incomplete' status" do
          subscription = create(:subscription, state: 'processing', plan: plan, stripe_token: token)

          allow(Stripe::Subscription).to receive(:create).and_return(
            mock_stripe_subscription('incomplete', plan.amount)
          )

          StartSubscription.call(subscription)

          expect(subscription.reload.processing?).to be true
          expect(subscription.reload.stripe_status).to eq 'incomplete'
        end
      end
    end
  end
end
