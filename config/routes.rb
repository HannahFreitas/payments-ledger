Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :accounts, only: %i[create show] do
    resources :entries, only: :index
  end
  resources :transfers, only: %i[create show]
end
