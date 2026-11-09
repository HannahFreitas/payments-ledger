module LedgerHelpers
  def customer(currency: "BRL", name: "Customer")
    Account.create!(name:, currency:, kind: "customer")
  end

  def funding(currency: "BRL")
    Account.create!(name: "Funding #{currency}", currency:, kind: "system")
  end

  # Puts money into an account the only way the ledger allows: a transfer from a system account.
  def fund(account, cents)
    Ledger::PostTransfer.call(from_account_id: funding(currency: account.currency).id, to_account_id: account.id,
                              amount_cents: cents, currency: account.currency)
    account.reload
  end
end

RSpec.configure { |config| config.include LedgerHelpers }
