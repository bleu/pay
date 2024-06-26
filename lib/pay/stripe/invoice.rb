module Pay
  module Stripe
    class Invoice
      attr_accessor :stripe_subscription
      attr_reader :pay_invoice

      delegate :amount,
        :amount_due,
        :currency,
        :status,
        :payment_intent_id,
        :processor_id,
        to: :pay_invoice

      def initialize(pay_invoice)
        @pay_invoice = pay_invoice
      end

      def invoice(**options)
        options[:id] = processor_id
        @stripe_invoice ||= ::Stripe::Invoice.retrieve(options.merge(expand_options))
      end

      def reload!
        @stripe_invoice = nil
      end

      def self.sync(invoice_id, object: nil, stripe_account: nil, try: 0, retries: 1)
        object ||= ::Stripe::Invoice.retrieve({id: invoice_id}.merge(expand_options))

        pay_customer = Pay::Customer.find_by(processor: :stripe, processor_id: object.customer)
        if pay_customer.blank?
          Rails.logger.debug "Pay::Customer #{object.customer} not found while syncing Stripe Invoice #{object.id}"
          return
        end

        attrs = {
          subscription: pay_customer.subscriptions.find_by(processor_id: object.subscription),
          amount_due: object.amount_due,
          currency: object.currency,
          status: object.status,
          due_date: object.due_date ? Time.at(object.due_date) : nil,
          paid_at: object.status == "paid" ? object.status_transitions&.paid_at ? Time.at(object.status_transitions.paid_at) : Time.at(object.created) : nil,
          invoice_pdf_url: object.invoice_pdf,
          hosted_invoice_url: object.hosted_invoice_url,
          processor_plan_id: object.subscription&.plan&.id,
          number: object.number,
          total: object.total,
          period_start: object.lines.data.first&.period&.start ? Time.at(object.lines.data.first.period.start) : nil,
          period_end: object.lines.data.first&.period&.end ? Time.at(object.lines.data.first.period.end) : nil,
          line_items: object.lines.data.map do |line_item|
            {
              id: line_item.id,
              amount: line_item.amount,
              description: line_item.description,
              quantity: line_item.quantity,
              unit_amount: line_item.price&.unit_amount,
              plan_id: line_item.plan&.id,
              price_id: line_item.price&.id,
            }
          end
        }

        pay_invoice = pay_customer.invoices.find_or_initialize_by(processor_id: object.id)
        pay_invoice.assign_attributes(attrs)
        pay_invoice.save!
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        try += 1
        if try <= retries
          sleep 0.1
          retry
        else
          raise
        end
      end

      def self.expand_options
        {
          expand: [
            "customer",
            "lines",
            "charge",
            "subscription.plan",
          ]
        }
      end

      def expand_options
        self.class.expand_options
      end
    end
  end
end
