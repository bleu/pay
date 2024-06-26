class CreatePayInvoices < ActiveRecord::Migration[6.0]
  def change
    primary_key_type, foreign_key_type = primary_and_foreign_key_types

    create_table :pay_invoices, id: primary_key_type do |t|
      t.belongs_to :customer, foreign_key: {to_table: :pay_customers}, null: false, type: foreign_key_type
      t.belongs_to :subscription, foreign_key: {to_table: :pay_subscriptions}, null: true, type: foreign_key_type
      t.string :processor_id, null: false
      t.string :status, null: false
      t.integer :amount_due
      t.integer :number
      t.datetime :due_date
      t.datetime :paid_at
      t.integer :total
      t.datetime :period_start
      t.datetime :period_end
      t.string :stripe_account
      t.public_send Pay::Adapter.json_column_type, :data

      t.timestamps
    end

    add_index :pay_invoices, [:customer_id, :processor_id], unique: true
  end

  private

  def primary_and_foreign_key_types
    config = Rails.configuration.generators
    setting = config.options[config.orm][:primary_key_type]
    primary_key_type = setting || :primary_key
    foreign_key_type = setting || :bigint
    [primary_key_type, foreign_key_type]
  end
end
