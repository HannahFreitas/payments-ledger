# 0001: Money as integer cents and an ISO 4217 currency

**Status:** accepted

## Context

Binary floating point cannot represent most decimal fractions exactly: `0.1 + 0.2` is `0.30000000000000004`.
In a ledger, those errors accumulate across millions of operations and show up as cents that nobody can explain.

## Decision

Store every amount as a `bigint` number of the currency's minor unit (cents for BRL and USD), together with a
three-letter ISO 4217 code. The API accepts only integers: `"100"`, `1.5` and `0` are rejected.

A transfer must be in the same currency as both accounts. Conversion is out of scope, and guessing a rate would
be worse than refusing.

## Alternatives considered

- **`decimal` columns.** Exact, but they invite fractional cents and make every comparison depend on scale.
- **A money gem.** Useful when there are many currencies and formatting needs. Here it would hide the one rule
  that matters, which is simple enough to keep visible.

## Consequences

Currencies with three decimal places (like KWD) would need the minor unit per currency. With BRL and USD it is
always 2, so this is not modelled yet.
