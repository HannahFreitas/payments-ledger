require "rails_helper"

RSpec.describe "Transfers API" do
  let(:alice) { fund(customer(name: "Alice"), 10_000) }
  let(:bob) { customer(name: "Bob") }
  let(:payload) { { from_account_id: alice.id, to_account_id: bob.id, amount_cents: 1_500, currency: "BRL", description: "rent" } }

  def post_transfer(body, key: "key-1")
    headers = key ? { "Idempotency-Key" => key } : {}
    post "/transfers", params: body, headers:, as: :json
  end

  it "creates a transfer and returns both entries" do
    post_transfer(payload)

    expect(response).to have_http_status(:created)
    expect(response.headers["Idempotent-Replayed"]).to eq("false")
    expect(response.parsed_body).to include("amount_cents" => 1_500, "currency" => "BRL", "description" => "rent")
    expect(response.parsed_body["entries"].sum { |e| e["amount_cents"] }).to eq(0)
    expect(bob.reload.balance_cents).to eq(1_500)
  end

  it "replays the first response for a retry with the same key, and moves the money once" do
    post_transfer(payload)
    first = response.body

    expect { post_transfer(payload) }.not_to change(Transfer, :count)
    expect(response).to have_http_status(:created)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
    expect(response.body).to eq(first) # byte for byte, not just the same keys
    expect(bob.reload.balance_cents).to eq(1_500)
  end

  it "rejects the same key with a different body" do
    post_transfer(payload)
    post_transfer(payload.merge(amount_cents: 1_600))

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.parsed_body["code"]).to eq("idempotency_key_reused")
  end

  it "requires an Idempotency-Key" do
    post_transfer(payload, key: nil)
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["code"]).to eq("idempotency_key_required")
  end

  it "rejects an Idempotency-Key longer than 255 characters" do
    post_transfer(payload, key: "k" * 256)
    expect(response.parsed_body["code"]).to eq("idempotency_key_too_long")
  end

  it "answers insufficient funds as a 422 problem, and replays that same answer later" do
    post_transfer(payload.merge(amount_cents: 20_000), key: "big")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include("code" => "insufficient_funds", "status" => 422)

    fund(alice, 50_000) # the account can afford it now
    post_transfer(payload.merge(amount_cents: 20_000), key: "big")
    expect(response.parsed_body["code"]).to eq("insufficient_funds")
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
    expect(bob.reload.balance_cents).to eq(0)
  end

  it "shows a transfer, and 404s as a problem for an unknown one" do
    post_transfer(payload)
    get "/transfers/#{response.parsed_body['id']}"
    expect(response.parsed_body["entries"].size).to eq(2)

    get "/transfers/0"
    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/problem+json")
  end
end
