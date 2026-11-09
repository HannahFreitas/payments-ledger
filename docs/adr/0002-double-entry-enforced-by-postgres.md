# 0002: Double entry, enforced by Postgres

**Status:** accepted

## Context

A ledger is correct only if money is never created or destroyed: every amount that leaves one account must
enter another. If only the application code guarantees that, any bug, refactor or manual SQL fix can break it
silently, and the error is found weeks later during reconciliation.

## Decision

- Every transfer writes two `entries`: a negative one on the source account and a positive one on the
  destination.
- A `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` checks, at `COMMIT`, that the entries of every
  transfer touched in the transaction sum to zero. Deferred, because the two entries are inserted one after the
  other, and the transfer is unbalanced in between.
- Entries are append-only: another trigger rejects `UPDATE` and `DELETE`. Corrections are new transfers, which
  keeps the history auditable.
- Customer balances cannot go negative: a check constraint on `accounts`.
- The cached `balance_cents` on each account is checked against its entries by `bin/rails ledger:audit`.

The schema is dumped as `db/structure.sql`, because `schema.rb` cannot represent triggers.

## Alternatives considered

- **Validations only in Ruby.** Cheaper to write, but they protect only the code path that calls them.
- **No cached balance, always `SUM(entries)`.** Always correct, but every balance read and every funds check
  becomes a scan that grows with history. The cache is protected by the same row lock that serialises
  transfers, and the audit proves it matches.

## Consequences

Tests that need to see the deferred check use `SET CONSTRAINTS ALL IMMEDIATE`, because the per-test
transaction never commits.
