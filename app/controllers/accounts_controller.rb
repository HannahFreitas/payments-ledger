class AccountsController < ApplicationController
  wrap_parameters false

  def create
    account = Account.create!(params.permit(:name, :currency, :kind))
    render json: Api.account(account), status: :created
  end

  def show
    render json: Api.account(Account.find(params[:id]))
  end
end
