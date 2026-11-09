class ApplicationController < ActionController::API
  PROBLEM_JSON = "application/problem+json".freeze

  rescue_from ActiveRecord::RecordNotFound do |e|
    render_problem(404, "not_found", "#{e.model || 'Record'} not found")
  end
  rescue_from ActionController::ParameterMissing do |e|
    render_problem(400, "bad_request", e.message)
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    render_problem(422, "invalid_record", e.record.errors.full_messages.to_sentence)
  end

  private

  def render_problem(status, code, detail)
    render json: Api.problem(status:, code:, detail:), status:, content_type: PROBLEM_JSON
  end
end
