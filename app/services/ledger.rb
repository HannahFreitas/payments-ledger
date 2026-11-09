# The ledger domain: posting transfers, auditing balances, and the business errors they can raise.
module Ledger
  # Business outcomes that the API reports as 422. They are deterministic for a given request, so an
  # idempotent replay returns the same error instead of trying again.
  class Error < StandardError
    def code = self.class.name.demodulize.underscore
  end

  class InsufficientFunds < Error; end
  class CurrencyMismatch < Error; end
  class SameAccount < Error; end
  class AccountNotFound < Error; end
  class InvalidAmount < Error; end
end
