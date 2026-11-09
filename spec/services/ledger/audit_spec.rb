require "rails_helper"

RSpec.describe Ledger::Audit do
  it "passes on a ledger built only through transfers" do
    alice = fund(customer, 500)
    Ledger::PostTransfer.call(from_account_id: alice.id, to_account_id: customer(name: "Bob").id, amount_cents: 200, currency: "BRL")
    expect(described_class.call).to eq(ok: true, problems: [])
  end

  it "catches a cached balance that disagrees with the entries" do
    alice = fund(customer, 500)
    alice.update_columns(balance_cents: 900) # what a bad manual fix in production looks like

    result = described_class.call
    expect(result[:ok]).to be(false)
    expect(result[:problems]).to include("account #{alice.id}: cached 900, entries sum to 500")
    expect(result[:problems]).to include("currency BRL: balances sum to 400")
  end
end
