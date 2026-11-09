# 0003: Row locks on both accounts, in a fixed order

**Status:** accepted

## Context

Two transfers can touch the same account at the same time. Reading the balance, checking it and writing it
back without a lock loses updates: both read 100, both subtract 80, and the account ends at 20 after moving 160.

## Decision

Lock both account rows with `SELECT ... FOR UPDATE` before checking funds, **always in ascending id order**.

If each transfer locked its own source account first, A to B and B to A could each hold one lock and wait for
the other forever. Postgres would detect the deadlock and kill one of them, turning normal traffic into errors.
Ordering by id gives every transaction the same lock order, so the cycle cannot form.

## Alternatives considered

- **Optimistic locking (`lock_version`).** No blocking, but under contention most attempts fail and retry,
  which is the worst case for a hot account.
- **A single global lock.** Correct and simple, but it serialises every transfer in the system.

## Evidence

`spec/concurrency/concurrent_transfers_spec.rb` runs 240 transfers from 8 threads in random directions. With
the locks removed, or taken in request order, the spec fails.
