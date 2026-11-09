# Runs a request at most once per Idempotency-Key, and replays the stored response for retries.
#
# Everything happens in ONE database transaction: the advisory lock on the key, the work, and the stored
# response. There is no window in which the money moved but the response was not recorded, and no
# "in progress" state to clean up after a crash: if the transaction rolls back, the key was never used.
#
# The response is stored as the exact JSON text that was sent, so a replay is byte-for-byte the same.
#
# A concurrent request with the same key blocks on the advisory lock until the first one commits, then finds
# the stored response and replays it. The lock is transaction-scoped, so it is released at COMMIT or ROLLBACK.
class Idempotency
  Result = Data.define(:status, :body, :replayed)

  # The same key was sent with a different request body. Replaying would answer a question the client did
  # not ask, and processing would apply the operation twice.
  class KeyReuse < StandardError; end

  def self.call(key:, fingerprint:)
    ApplicationRecord.transaction do
      lock!(key)
      if (stored = IdempotencyKey.find_by(key:))
        raise KeyReuse, "Idempotency-Key was already used with a different request" unless stored.request_fingerprint == fingerprint

        next Result.new(status: stored.response_status, body: stored.response_body, replayed: true)
      end

      status, body = yield
      json = body.is_a?(String) ? body : JSON.generate(body)
      IdempotencyKey.create!(key:, request_fingerprint: fingerprint, response_status: status, response_body: json)
      Result.new(status:, body: json, replayed: false)
    end
  end

  def self.fingerprint(method, path, params)
    Digest::SHA256.hexdigest([ method, path, JSON.generate(params.sort.to_h) ].join("\n"))
  end

  def self.lock!(key)
    sql = ApplicationRecord.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", key ])
    ApplicationRecord.connection.execute(sql)
  end
  private_class_method :lock!
end
