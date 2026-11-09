require "rails_helper"

# The rules that keep money correct are enforced by Postgres, so a bug in Ruby (or a manual SQL fix in
# production) cannot break them. These specs bypass the service on purpose.
RSpec.describe "database invariants" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:alice) { fund(customer(name: "Alice"), 1_000) }
  let(:bob) { customer(name: "Bob") }

  def raw_transfer(amount)
    Transfer.create!(from_account: alice, to_account: bob, amount_cents: amount, currency: "BRL")
  end

  it "rejects a transfer whose entries do not sum to zero" do
    t = raw_transfer(100)
    Entry.create!(transfer: t, account: alice, amount_cents: -100, balance_after_cents: 900)
    Entry.create!(transfer: t, account: bob, amount_cents: 90, balance_after_cents: 90)

    # The check is deferred to COMMIT; this makes it run now, inside the test's transaction.
    expect { connection.execute("SET CONSTRAINTS ALL IMMEDIATE") }
      .to raise_error(ActiveRecord::StatementInvalid, /unbalanced: entries sum to -10/)
  end

  it "accepts a balanced transfer under the same check" do
    t = raw_transfer(100)
    Entry.create!(transfer: t, account: alice, amount_cents: -100, balance_after_cents: 900)
    Entry.create!(transfer: t, account: bob, amount_cents: 100, balance_after_cents: 100)
    expect { connection.execute("SET CONSTRAINTS ALL IMMEDIATE") }.not_to raise_error
  end

  it "rejects a negative balance on a customer account" do
    expect { alice.update_columns(balance_cents: -1) }.to raise_error(ActiveRecord::CheckViolation)
  end

  %w[UPDATE DELETE].each do |verb|
    it "keeps entries append-only: #{verb} is rejected" do
      entry = alice.entries.first
      sql = verb == "UPDATE" ? "UPDATE entries SET amount_cents = 1 WHERE id = #{entry.id}" : "DELETE FROM entries WHERE id = #{entry.id}"
      expect { connection.execute(sql) }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    end
  end

  it "rejects a zero transfer amount" do
    expect { raw_transfer(0) }.to raise_error(ActiveRecord::CheckViolation, /transfers_amount_positive/)
  end

  it "rejects a transfer to the same account" do
    expect { Transfer.create!(from_account: alice, to_account: alice, amount_cents: 1, currency: "BRL") }
      .to raise_error(ActiveRecord::CheckViolation, /transfers_distinct_accounts/)
  end
end
