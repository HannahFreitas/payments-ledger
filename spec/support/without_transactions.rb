# Concurrency specs need real commits seen by other connections, so they run outside the per-test
# transaction and clean up by truncating the ledger tables afterwards.
RSpec.shared_context "without transactional tests" do
  self.use_transactional_tests = false

  after do
    ActiveRecord::Base.connection.execute(
      "TRUNCATE entries, transfers, idempotency_keys, accounts RESTART IDENTITY CASCADE"
    )
  end
end
