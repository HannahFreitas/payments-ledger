class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :currency, null: false, limit: 3
      t.string :kind, null: false, default: "customer"
      t.bigint :balance_cents, null: false, default: 0
      t.timestamps
    end

    add_check_constraint :accounts, "currency ~ '^[A-Z]{3}$'", name: "accounts_currency_iso4217"
    add_check_constraint :accounts, "kind IN ('customer', 'system')", name: "accounts_kind_known"
    # Customer money cannot go below zero. System accounts (funding, fees) are allowed to, because they
    # are the other side of money entering or leaving the ledger.
    add_check_constraint :accounts, "kind = 'system' OR balance_cents >= 0", name: "accounts_customer_not_negative"
  end
end
