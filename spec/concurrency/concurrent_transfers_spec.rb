require "rails_helper"

# Real threads, real connections, real commits. These would fail with lost updates or deadlocks if the
# service read balances without locking, or locked the two accounts in request order.
RSpec.describe "concurrent transfers" do
  include_context "without transactional tests"

  def in_threads(count, &block)
    count.times.map { |i| Thread.new { ActiveRecord::Base.connection_pool.with_connection { block.call(i) } } }.map(&:value)
  end

  it "never loses money, never overdraws, and never deadlocks under opposite-direction traffic" do
    accounts = 4.times.map { |i| fund(customer(name: "C#{i}"), 1_000) }
    total = accounts.sum(&:balance_cents)

    outcomes = in_threads(8) do |seed|
      rng = Random.new(seed)
      30.times.map do
        from, to = accounts.sample(2, random: rng)
        Ledger::PostTransfer.call(from_account_id: from.id, to_account_id: to.id, amount_cents: rng.rand(1..400), currency: "BRL")
        :ok
      rescue Ledger::InsufficientFunds
        :insufficient
      end
    end.flatten

    balances = accounts.map { |a| a.reload.balance_cents }
    expect(outcomes.size).to eq(240)
    expect(outcomes).to include(:ok)
    expect(balances.sum).to eq(total)
    expect(balances).to all(be >= 0)
    expect(Ledger::Audit.call).to eq(ok: true, problems: [])
  end

  it "applies a transfer once when the same Idempotency-Key arrives on many connections at the same time" do
    alice = fund(customer(name: "Alice"), 1_000)
    bob = customer(name: "Bob")
    fields = { from_account_id: alice.id, to_account_id: bob.id, amount_cents: 300, currency: "BRL" }
    fingerprint = Idempotency.fingerprint("POST", "/transfers", fields)

    results = in_threads(8) do
      Idempotency.call(key: "same-key", fingerprint:) { [ 201, Api.transfer(Ledger::PostTransfer.call(**fields)) ] }
    end

    expect(results.map(&:body).uniq.size).to eq(1)
    expect(results.count(&:replayed)).to eq(7)
    expect(bob.reload.balance_cents).to eq(300)
    expect(Transfer.where(to_account_id: bob.id).count).to eq(1)
  end
end
