Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :inventory, param: :sku, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :adjust
          post :reserve
          post :release
          post :commit
          get :movements
        end

        collection do
          get :low_stock
          get :locations
          post :bulk_adjust
        end
      end

      # Stock movements (read-only)
      resources :stock_movements, only: [:index, :show]
    end
  end

  # Health checks
  get "/health", to: "health#show"
  get "/health/ready", to: "health#ready"
  get "/health/live", to: "health#live"

  # Root
  root to: proc { [200, {}, [{ service: "inventory", version: "1.0.0" }.to_json]] }
end
