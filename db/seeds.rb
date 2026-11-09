# A system account per currency is where money enters the ledger (think: deposits from a bank).
# It is the only kind of account allowed to go negative.
%w[BRL USD].each do |currency|
  Account.find_or_create_by!(name: "Funding #{currency}", currency:, kind: "system")
end
