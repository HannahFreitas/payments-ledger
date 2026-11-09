# An account's statement, newest first, with keyset pagination: `?before=<entry id>&limit=50`.
# Offset pagination would skip or repeat rows while new entries arrive; a cursor on the primary key does not.
class EntriesController < ApplicationController
  MAX_LIMIT = 100

  def index
    account = Account.find(params[:account_id])
    limit = params.fetch(:limit, 50).to_i.clamp(1, MAX_LIMIT)
    scope = account.entries.order(id: :desc).limit(limit + 1)
    scope = scope.where(id: ...Integer(params[:before])) if params[:before].present?

    page = scope.to_a
    has_more = page.size > limit
    page = page.first(limit)
    render json: { data: page.map { |e| Api.entry(e) }, next_cursor: has_more ? page.last.id : nil }
  rescue ArgumentError
    render_problem(400, "bad_request", "before must be an entry id")
  end
end
