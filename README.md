# payments-ledger

[![CI](https://github.com/HannahFreitas/payments-ledger/actions/workflows/ci.yml/badge.svg)](https://github.com/HannahFreitas/payments-ledger/actions/workflows/ci.yml)

A double-entry ledger API for moving money between accounts, built with **Rails 8.1** and **PostgreSQL 18**.

It is small on purpose. The goal is to show how I handle the parts of a payments system that are easy to get
wrong and expensive to fix later: money that must never be created or lost, retries that must never charge
twice, and concurrent requests that must never overdraw an account.

## What it guarantees, and where each guarantee lives

| Guarantee | How | Enforced by |
|---|---|---|
| Every transfer balances: what leaves one account enters the other | Each transfer writes two entries that sum to zero | A **deferred constraint trigger** in Postgres, checked at `COMMIT` |
| A customer account never goes negative | Balance check under a row lock | A **check constraint** in Postgres, plus the service |
| The ledger is never rewritten | Corrections are new transfers | A **trigger that rejects `UPDATE` and `DELETE`** on entries |
| A retried request moves money once | `Idempotency-Key` header, response stored in the same transaction | A **transaction-scoped advisory lock** on the key, plus a unique index |
| Concurrent transfers do not deadlock or lose updates | `SELECT ... FOR UPDATE` on both accounts, always in ascending id order | Postgres row locks |
| Cached balances can be trusted | Every balance can be recomputed from its entries | `bin/rails ledger:audit` |

The database is the last line of defence on purpose. A bug in the Ruby code, a future refactor, or a manual SQL
fix in production still cannot produce an unbalanced transfer or a negative customer balance.

## Design decisions

Each decision has a short record in [`docs/adr`](docs/adr) with the alternatives I considered.

- **Integer cents, never floats.** `0.1 + 0.2` is not `0.3` in binary floating point. Amounts are `bigint` cents
  and an ISO 4217 currency, and a transfer between currencies is rejected instead of guessed.
  ([ADR 0001](docs/adr/0001-money-as-integer-cents.md))
- **Double entry, enforced by the database.** The service writes the two entries, and a deferred constraint
  trigger refuses to commit any transfer whose entries do not sum to zero.
  ([ADR 0002](docs/adr/0002-double-entry-enforced-by-postgres.md))
- **Locks in a fixed order.** Two transfers in opposite directions (A to B and B to A) lock the same two rows. If
  each locked its own source first, they could deadlock. Locking by ascending id makes the order the same for
  everyone. ([ADR 0003](docs/adr/0003-row-locks-in-a-fixed-order.md))
- **Idempotency inside the same transaction as the work.** The key, the transfer and the stored response commit
  or roll back together. There is no "in progress" row to clean up after a crash, and no window in which the
  money moved but the response was lost. A concurrent duplicate waits on the advisory lock and then replays the
  stored response, byte for byte. ([ADR 0004](docs/adr/0004-idempotency-in-the-same-transaction.md))
- **Business errors are replayed too.** If a transfer was refused for insufficient funds, retrying the same key
  returns the same refusal, even if the account has money now. A retry is the same request, not a new one.
- **Keyset pagination for statements.** `?before=<entry id>` instead of `?page=2`, so new entries arriving
  between requests never shift a page and cause skipped or repeated rows.
- **Errors as [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) Problem Details** (`application/problem+json`),
  with a stable `code` field that clients can branch on.

## API

| Method | Path | Notes |
|---|---|---|
| `POST` | `/accounts` | `name`, `currency` (ISO 4217), optional `kind` (`customer` or `system`) |
| `GET` | `/accounts/:id` | Includes the current `balance_cents` |
| `GET` | `/accounts/:id/entries` | Statement, newest first. `limit` (max 100) and `before` cursor |
| `POST` | `/transfers` | Requires an `Idempotency-Key` header |
| `GET` | `/transfers/:id` | The transfer and its two entries |

Money enters the ledger through a `system` account, the only kind allowed to go negative. Think of it as the
bank side of a deposit.

```bash
# a customer, and a funding account for BRL (also created by db:seed)
curl -s -X POST localhost:3000/accounts -H 'Content-Type: application/json' -d '{"name":"Alice","currency":"BRL"}'
curl -s -X POST localhost:3000/accounts -H 'Content-Type: application/json' -d '{"name":"Funding BRL","currency":"BRL","kind":"system"}'

# move R$ 150,00 from funding (id 2) to Alice (id 1)
curl -s -X POST localhost:3000/transfers \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: deposit-0001' \
  -d '{"from_account_id":2,"to_account_id":1,"amount_cents":15000,"currency":"BRL","description":"deposit"}'

# send the same request again: same response, header Idempotent-Replayed: true, money moved once
```

A refused transfer looks like this:

```json
{
  "type": "https://github.com/HannahFreitas/payments-ledger#errors",
  "title": "Insufficient funds",
  "status": 422,
  "code": "insufficient_funds",
  "detail": "account 1 has 15000 cents, transfer needs 20000"
}
```

### Errors

| Status | `code` | When |
|---|---|---|
| 400 | `idempotency_key_required`, `idempotency_key_too_long`, `bad_request` | The request is malformed |
| 404 | `not_found` | The account or transfer does not exist |
| 422 | `insufficient_funds`, `currency_mismatch`, `same_account`, `account_not_found`, `invalid_amount` | The ledger refused the transfer |
| 422 | `idempotency_key_reused` | The same key was sent with a different body |
| 422 | `invalid_record` | Account validation failed |

## Running it

Requirements: Ruby 4.0.9 and Docker (for Postgres).

```bash
docker compose up -d db        # Postgres 18.6 on port 5544, isolated from anything else on the machine
bundle install
bin/rails db:prepare db:seed
bin/rails server

bin/rails ledger:audit         # recompute every balance from its entries
```

## Tests

```bash
bundle exec rspec
```

37 examples, about 96% line coverage. The ones I would read first:

- [`spec/concurrency`](spec/concurrency/concurrent_transfers_spec.rb): 8 threads with their own database
  connections send 240 transfers in random directions between 4 accounts. The total is conserved, no balance
  goes negative, nothing deadlocks, and the audit passes. A second spec sends the same `Idempotency-Key` from 8
  connections at once and checks that the money moves exactly once.
- [`spec/db/invariants_spec.rb`](spec/db/invariants_spec.rb): bypasses the service and writes to the tables
  directly, to prove the database itself rejects an unbalanced transfer, a negative customer balance and an
  edit to an entry.

To check that the specs test something, I removed each critical guard on purpose (the row lock, the lock
ordering, the idempotency lock, the funds check) and confirmed that a spec fails every time.

CI runs on every push: Brakeman, bundler-audit, RuboCop, and the full suite against Postgres 18.6.

## Out of scope, for now

- **Webhooks for `transfer.completed`**, through a transactional outbox and Solid Queue, signed with HMAC and
  retried with backoff. Next on the list.
- Authentication and per-client idempotency scopes. Keys are global here.
- Currency conversion. Transfers between currencies are rejected.
- Expiring old idempotency keys.

## License

[MIT](LICENSE)
