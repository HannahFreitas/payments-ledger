class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      t.integer :response_status, null: false
      # Text, not jsonb: jsonb reorders keys, and a replay must return the exact bytes of the first response.
      t.text :response_body, null: false
      t.datetime :created_at, null: false
    end

    add_index :idempotency_keys, :key, unique: true
    add_check_constraint :idempotency_keys, "char_length(key) BETWEEN 1 AND 255", name: "idempotency_keys_key_length"
  end
end
