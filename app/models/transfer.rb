class Transfer < ApplicationRecord
  belongs_to :from_account, class_name: "Account"
  belongs_to :to_account, class_name: "Account"
  has_many :entries, -> { order(:id) }, dependent: :restrict_with_exception

  # Rows are written once by Ledger::PostTransfer and never changed afterwards.
  def readonly?
    persisted?
  end
end
