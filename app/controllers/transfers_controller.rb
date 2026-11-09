class TransfersController < ApplicationController
  wrap_parameters false

  TRANSFER_FIELDS = %i[from_account_id to_account_id amount_cents currency description].freeze

  def create
    key = request.headers["Idempotency-Key"]
    return render_problem(400, "idempotency_key_required", "send an Idempotency-Key header") if key.blank?
    return render_problem(400, "idempotency_key_too_long", "Idempotency-Key is limited to 255 characters") if key.length > 255

    fields = params.permit(*TRANSFER_FIELDS).to_h.symbolize_keys
    fingerprint = Idempotency.fingerprint(request.method, request.path, fields)

    result = Idempotency.call(key:, fingerprint:) do
      transfer = Ledger::PostTransfer.call(**fields.slice(*TRANSFER_FIELDS))
      [ 201, Api.transfer(transfer) ]
    rescue Ledger::Error => e
      [ 422, Api.problem(status: 422, code: e.code, detail: e.message) ]
    end

    response.set_header("Idempotent-Replayed", result.replayed.to_s)
    render json: result.body, status: result.status,
           content_type: result.status >= 400 ? PROBLEM_JSON : "application/json"
  rescue Idempotency::KeyReuse => e
    render_problem(422, "idempotency_key_reused", e.message)
  end

  def show
    render json: Api.transfer(Transfer.includes(:entries).find(params[:id]))
  end
end
