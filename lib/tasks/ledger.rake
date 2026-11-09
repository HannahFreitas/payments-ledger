namespace :ledger do
  desc "Recompute balances from entries and fail if anything disagrees"
  task audit: :environment do
    result = Ledger::Audit.call
    if result[:ok]
      puts "ledger OK"
    else
      warn result[:problems].join("\n")
      abort "ledger audit failed: #{result[:problems].size} problem(s)"
    end
  end
end
