class CreateTransfersAndEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :transfers do |t|
      t.references :from_account, null: false, foreign_key: { to_table: :accounts }
      t.references :to_account, null: false, foreign_key: { to_table: :accounts }
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, limit: 3
      t.string :description
      t.datetime :created_at, null: false
    end

    add_check_constraint :transfers, "amount_cents > 0", name: "transfers_amount_positive"
    add_check_constraint :transfers, "from_account_id <> to_account_id", name: "transfers_distinct_accounts"

    # One row per side of a transfer. A negative amount leaves an account, a positive one enters it.
    create_table :entries do |t|
      t.references :transfer, null: false, foreign_key: true, index: true
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :amount_cents, null: false
      t.bigint :balance_after_cents, null: false
      t.datetime :created_at, null: false
    end

    add_check_constraint :entries, "amount_cents <> 0", name: "entries_amount_not_zero"
    # Statements page through an account's entries newest first; this index serves the keyset cursor.
    add_index :entries, [ :account_id, :id ], order: { id: :desc }

    reversible do |dir|
      dir.up do
        # Double entry, enforced by Postgres and not only by Ruby: at COMMIT, every transfer touched in the
        # transaction must have entries summing to zero. DEFERRABLE INITIALLY DEFERRED lets both entries be
        # inserted before the check runs.
        execute <<~SQL
          CREATE FUNCTION entries_balanced() RETURNS trigger AS $$
          DECLARE
            total bigint;
          BEGIN
            SELECT COALESCE(SUM(amount_cents), 0) INTO total FROM entries WHERE transfer_id = NEW.transfer_id;
            IF total <> 0 THEN
              RAISE EXCEPTION 'transfer % is unbalanced: entries sum to %', NEW.transfer_id, total
                USING ERRCODE = 'check_violation';
            END IF;
            RETURN NULL;
          END;
          $$ LANGUAGE plpgsql;

          CREATE CONSTRAINT TRIGGER entries_must_balance
            AFTER INSERT OR UPDATE ON entries
            DEFERRABLE INITIALLY DEFERRED
            FOR EACH ROW EXECUTE FUNCTION entries_balanced();

          -- The ledger is append-only: entries are never edited or removed. Corrections are new transfers.
          CREATE FUNCTION entries_append_only() RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'entries are append-only' USING ERRCODE = 'insufficient_privilege';
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER entries_no_update_or_delete
            BEFORE UPDATE OR DELETE ON entries
            FOR EACH ROW EXECUTE FUNCTION entries_append_only();
        SQL
      end
      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS entries_no_update_or_delete ON entries;
          DROP FUNCTION IF EXISTS entries_append_only();
          DROP TRIGGER IF EXISTS entries_must_balance ON entries;
          DROP FUNCTION IF EXISTS entries_balanced();
        SQL
      end
    end
  end
end
