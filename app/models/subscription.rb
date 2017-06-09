class Subscription < ActiveRecord::Base
  include Pay

  # Associations
  belongs_to :owner, class_name: Pay.billable_class, foreign_key: :owner_id

  # Validations
  validates :name, presence: true
  validates :processor, presence: true
  validates :processor_id, presence: true
  validates :processor_plan, presence: true
  validates :quantity, presence: true

  # Instance Methods
  def create_with_processor
    subscription = new_stripe_subscription

    update!(
      processor_id: subscription.id,
      trial_ends_at: find_trial_ends_at(subscription),
      quantity: quantity || 1,
      ends_at: nil
    )

    self
  end

  def on_trial?
    trial_ends_at? && Time.zone.now < trial_ends_at
  end

  def cancelled?
    ends_at?
  end

  def on_grace_period?
    cancelled? && Time.zone.now < ends_at
  end

  def active?
    ends_at.nil? || on_grace_period? || on_trial?
  end

  def cancel
    subscription = processor_subscription.delete(at_period_end: true)
    update(ends_at: Time.at(subscription.current_period_end))
  end

  def cancel_now!
    subscription = processor_subscription.delete
    update(ends_at: Time.at(subscription.current_period_end))
  end

  def resume
    unless on_grace_period?
      raise StandardError,
            'You can only resume subscriptions within their grace period.'
    end

    subscription = processor_subscription
    subscription.plan = processor_plan
    subscription.trial_end = on_trial? ? trial_ends_at.to_i : 'now'
    subscription.save

    update(ends_at: nil)
    self
  end

  def processor_subscription
    Stripe::Subscription.retrieve(processor_id)
  end

  def find_trial_ends_at(subscription)
    subscription.trial_end.present? ? Time.at(subscription.trial_end) : nil
  end

  private

  def new_stripe_subscription
    owner.processor_customer.subscriptions.create(plan: processor_plan)
  end
end