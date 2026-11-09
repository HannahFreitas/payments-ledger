# Plain hashes for the JSON API. Kept apart from the models so the wire format is explicit and versionable.
module Api
  module_function

  def account(account)
    { id: account.id, name: account.name, currency: account.currency, kind: account.kind,
      balance_cents: account.balance_cents }
  end

  def transfer(transfer)
    { id: transfer.id, from_account_id: transfer.from_account_id, to_account_id: transfer.to_account_id,
      amount_cents: transfer.amount_cents, currency: transfer.currency, description: transfer.description,
      created_at: transfer.created_at.iso8601(6),
      entries: transfer.entries.map { |e| entry(e) } }
  end

  def entry(entry)
    { id: entry.id, transfer_id: entry.transfer_id, account_id: entry.account_id, amount_cents: entry.amount_cents,
      balance_after_cents: entry.balance_after_cents, created_at: entry.created_at.iso8601(6) }
  end

  # RFC 9457 Problem Details.
  def problem(status:, code:, detail:)
    { type: "https://github.com/HannahFreitas/payments-ledger#errors", title: code.humanize, status:, code:, detail: }
  end
end
