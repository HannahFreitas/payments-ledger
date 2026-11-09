require "rails_helper"

RSpec.describe Idempotency do
  it "runs the work once and replays the stored response afterwards" do
    calls = 0
    work = -> { calls += 1; [ 201, { "id" => calls } ] }

    first = described_class.call(key: "k1", fingerprint: "f") { work.call }
    second = described_class.call(key: "k1", fingerprint: "f") { work.call }

    expect(calls).to eq(1)
    expect([ first.status, first.body, first.replayed ]).to eq([ 201, '{"id":1}', false ])
    expect([ second.status, second.body, second.replayed ]).to eq([ 201, '{"id":1}', true ])
  end

  it "refuses the same key with a different request" do
    described_class.call(key: "k2", fingerprint: "a") { [ 201, {} ] }
    expect { described_class.call(key: "k2", fingerprint: "b") { [ 201, {} ] } }.to raise_error(Idempotency::KeyReuse)
  end

  it "stores nothing when the work raises, so the client can retry with the same key" do
    expect { described_class.call(key: "k3", fingerprint: "f") { raise "database went away" } }.to raise_error("database went away")
    expect(IdempotencyKey.where(key: "k3")).to be_empty

    retried = described_class.call(key: "k3", fingerprint: "f") { [ 201, { "ok" => true } ] }
    expect(retried.replayed).to be(false)
  end

  it "fingerprints the request independently of the order of the fields" do
    a = described_class.fingerprint("POST", "/transfers", { amount_cents: 1, currency: "BRL" })
    b = described_class.fingerprint("POST", "/transfers", { currency: "BRL", amount_cents: 1 })
    expect(a).to eq(b)
    expect(described_class.fingerprint("POST", "/transfers", { amount_cents: 2, currency: "BRL" })).not_to eq(a)
  end
end
