require "rails_helper"

RSpec.describe "Accounts API" do
  it "creates and shows an account" do
    post "/accounts", params: { name: "Alice", currency: "BRL" }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("name" => "Alice", "currency" => "BRL", "kind" => "customer", "balance_cents" => 0)

    get "/accounts/#{response.parsed_body['id']}"
    expect(response.parsed_body["name"]).to eq("Alice")
  end

  it "rejects an invalid currency as a 422 problem" do
    post "/accounts", params: { name: "Alice", currency: "real" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["detail"]).to include("ISO 4217")
  end

  describe "statement" do
    let(:alice) { fund(customer(name: "Alice"), 1_000) }
    let(:bob) { customer(name: "Bob") }

    before do
      5.times do |i|
        Ledger::PostTransfer.call(from_account_id: alice.id, to_account_id: bob.id, amount_cents: 10 + i, currency: "BRL")
      end
    end

    it "pages newest first with a cursor, without gaps or repeats" do
      seen, cursor = [], nil
      loop do
        get "/accounts/#{bob.id}/entries", params: { limit: 2, before: cursor }.compact
        seen.concat(response.parsed_body["data"].map { |e| e["amount_cents"] })
        cursor = response.parsed_body["next_cursor"]
        break unless cursor
      end
      expect(seen).to eq([ 14, 13, 12, 11, 10 ])
    end

    it "rejects a cursor that is not an id" do
      get "/accounts/#{bob.id}/entries", params: { before: "abc" }
      expect(response).to have_http_status(:bad_request)
    end
  end
end
