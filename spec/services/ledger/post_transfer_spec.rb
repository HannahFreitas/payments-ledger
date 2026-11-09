require "rails_helper"

RSpec.describe Ledger::PostTransfer do
  let(:alice) { fund(customer(name: "Alice"), 10_000) }
  let(:bob) { customer(name: "Bob") }

  def transfer(from:, to:, cents:, currency: "BRL")
    described_class.call(from_account_id: from.id, to_account_id: to.id, amount_cents: cents, currency:)
  end

  it "moves money as two entries that sum to zero, with the running balance on each" do
    t = transfer(from: alice, to: bob, cents: 2_500)

    expect([ alice.reload.balance_cents, bob.reload.balance_cents ]).to eq([ 7_500, 2_500 ])
    expect(t.entries.map { |e| [ e.account_id, e.amount_cents, e.balance_after_cents ] })
      .to eq([ [ alice.id, -2_500, 7_500 ], [ bob.id, 2_500, 2_500 ] ])
  end

  it "refuses to overdraw a customer account and changes nothing" do
    expect { transfer(from: alice, to: bob, cents: 10_001) }.to raise_error(Ledger::InsufficientFunds)
    expect([ alice.reload.balance_cents, bob.reload.balance_cents ]).to eq([ 10_000, 0 ])
    expect(Transfer.count).to eq(1) # only the funding transfer
  end

  it "lets a system account go negative, because that is where money enters the ledger" do
    source = funding
    transfer(from: source, to: bob, cents: 500)
    expect(source.reload.balance_cents).to eq(-500)
  end

  it "rejects a currency that does not match both accounts" do
    usd = customer(currency: "USD")
    expect { transfer(from: alice, to: usd, cents: 100) }.to raise_error(Ledger::CurrencyMismatch)
    expect { transfer(from: alice, to: bob, cents: 100, currency: "USD") }.to raise_error(Ledger::CurrencyMismatch)
  end

  it "rejects the same account on both sides" do
    expect { transfer(from: alice, to: alice, cents: 100) }.to raise_error(Ledger::SameAccount)
  end

  it "rejects an account that does not exist" do
    expect { described_class.call(from_account_id: alice.id, to_account_id: 999_999, amount_cents: 1, currency: "BRL") }
      .to raise_error(Ledger::AccountNotFound, /999999/)
  end

  [ 0, -5, 1.5, "100", nil ].each do |amount|
    it "rejects amount_cents=#{amount.inspect}: money is a positive integer number of cents" do
      expect { described_class.call(from_account_id: alice.id, to_account_id: bob.id, amount_cents: amount, currency: "BRL") }
        .to raise_error(Ledger::InvalidAmount)
    end
  end
end
