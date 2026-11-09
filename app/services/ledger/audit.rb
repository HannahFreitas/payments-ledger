module Ledger
  # Recomputes the ledger from its entries and compares with what is stored. Read-only.
  #
  # It checks three things that must always hold:
  #   1. every account's cached balance equals the sum of its entries;
  #   2. every transfer has exactly two entries, and they sum to zero;
  #   3. per currency, all balances together sum to zero (money only moves, it is never created).
  class Audit
    def self.call
      problems = []

      Account.left_joins(:entries).group(:id, :balance_cents)
             .having("accounts.balance_cents <> COALESCE(SUM(entries.amount_cents), 0)")
             .pluck(:id, :balance_cents, Arel.sql("COALESCE(SUM(entries.amount_cents), 0)::bigint"))
             .each { |id, cached, real| problems << "account #{id}: cached #{cached}, entries sum to #{real}" }

      Entry.group(:transfer_id).having("COUNT(*) <> 2 OR SUM(amount_cents) <> 0")
           .pluck(:transfer_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(amount_cents)::bigint"))
           .each { |id, count, sum| problems << "transfer #{id}: #{count} entries summing to #{sum}" }

      Account.group(:currency).having("SUM(balance_cents) <> 0").pluck(:currency, Arel.sql("SUM(balance_cents)::bigint"))
             .each { |currency, total| problems << "currency #{currency}: balances sum to #{total}" }

      { ok: problems.empty?, problems: }
    end
  end
end
