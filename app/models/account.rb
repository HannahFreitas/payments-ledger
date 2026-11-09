class Account < ApplicationRecord
  KINDS = %w[customer system].freeze

  has_many :entries, dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 120 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: "must be an ISO 4217 code, like BRL" }
  validates :kind, inclusion: { in: KINDS }

  def system?
    kind == "system"
  end
end
