# 0004: Idempotency in the same transaction as the work

**Status:** accepted

## Context

Clients retry: timeouts, dropped connections, a mobile app resending after it comes back online. Without
idempotency, a retry of "transfer R$ 100" moves R$ 200.

The common design stores the key first with an "in progress" status, does the work, then stores the result. It
has two gaps: if the process dies after the work and before the result is stored, the key is stuck "in
progress", and something has to decide later whether the money moved.

## Decision

`POST /transfers` requires an `Idempotency-Key` header. Inside **one** database transaction:

1. take `pg_advisory_xact_lock(hashtextextended(key, 0))`;
2. if a response is stored for the key, replay it, or refuse with `idempotency_key_reused` if the request body
   is different (compared by a SHA-256 fingerprint of method, path and sorted fields);
3. otherwise run the transfer and store the status and the exact JSON response.

The key, the transfer and the response commit or roll back together. A crash leaves nothing behind, and the
client can retry with the same key. A concurrent duplicate blocks on the advisory lock, then finds the stored
response. The lock is released at `COMMIT` or `ROLLBACK`, so it cannot leak.

The response is stored as text, not `jsonb`: `jsonb` reorders keys, and a replay should return the same bytes.

Business refusals (insufficient funds, currency mismatch) are stored and replayed too. The transfer runs in a
savepoint, so a refusal undoes only the transfer and the 422 is still recorded.

## Alternatives considered

- **Unique index only, insert the key first.** Simple, but the response would need a separate update, which
  reintroduces the "in progress" state.
- **Redis lock.** Another system to keep consistent with the database that holds the money.

## Consequences

The advisory lock key is a 64-bit hash, so two different keys can collide. A collision only makes one request
wait for the other; the stored response is still looked up by the full key.
