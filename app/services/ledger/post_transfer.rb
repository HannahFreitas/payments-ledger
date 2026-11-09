module Ledger
  # Moves money between two accounts as one double-entry transfer.
  #
  # Concurrency: both account rows are locked with SELECT ... FOR UPDATE, always in ascending id order. Two
  # transfers in opposite directions (A->B and B->A) therefore lock in the same order and cannot deadlock, and
  # the balance check runs on rows nobody else can change until COMMIT.
  #
  # The database is the last line of defence: it rejects a negative customer balance (check constraint) and an
  # unbalanced transfer (deferred constraint trigger), even if this class has a bug.
  class PostTransfer
    def self.call(...) = new(...).call

    def initialize(from_account_id:, to_account_id:, amount_cents:, currency:, description: nil)
      @from_id = Integer(from_account_id, exception: false)
      @to_id = Integer(to_account_id, exception: false)
      @amount = amount_cents
      @currency = currency.to_s.upcase
      @description = description
    end

    def call
      validate_request!

      # A savepoint: when called inside Idempotency, a business error undoes only the transfer, and the 422
      # response is still stored for replays.
      Transfer.transaction(requires_new: true) do
        from, to = lock_accounts
        check_currency!(from, to)
        check_funds!(from)

        transfer = Transfer.create!(from_account: from, to_account: to, amount_cents: @amount,
                                    currency: @currency, description: @description)
        post_entry!(transfer, from, -@amount)
        post_entry!(transfer, to, @amount)
        transfer
      end
    end

    private

    def validate_request!
      raise InvalidAmount, "amount_cents must be a positive integer" unless @amount.is_a?(Integer) && @amount.positive?
      raise AccountNotFound, "from_account_id and to_account_id are required" unless @from_id && @to_id
      raise SameAccount, "cannot transfer to the same account" if @from_id == @to_id
    end

    def lock_accounts
      locked = Account.where(id: [ @from_id, @to_id ]).order(:id).lock.index_by(&:id)
      missing = [ @from_id, @to_id ] - locked.keys
      raise AccountNotFound, "account #{missing.first} does not exist" if missing.any?

      [ locked.fetch(@from_id), locked.fetch(@to_id) ]
    end

    def check_currency!(from, to)
      return if from.currency == @currency && to.currency == @currency

      raise CurrencyMismatch, "transfer is in #{@currency}, accounts are in #{from.currency} and #{to.currency}"
    end

    def check_funds!(from)
      return if from.system? || from.balance_cents >= @amount

      raise InsufficientFunds, "account #{from.id} has #{from.balance_cents} cents, transfer needs #{@amount}"
    end

    def post_entry!(transfer, account, amount)
      account.update_columns(balance_cents: account.balance_cents + amount, updated_at: Time.current)
      Entry.create!(transfer:, account:, amount_cents: amount, balance_after_cents: account.balance_cents)
    end
  end
end
