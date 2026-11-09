class Entry < ApplicationRecord
  belongs_to :transfer
  belongs_to :account

  # The database rejects updates and deletes on entries (see the migration). This makes the intent visible in Ruby too.
  def readonly?
    persisted?
  end
end
