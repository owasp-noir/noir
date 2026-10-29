class ApiConstraint
  def get(request)
    true
  end
end

Rails.application.routes.draw do
  def patch(*)
  end # Disable PATCH requests

  def delete!(*)
  end

  namespace :api do
    scope :v1_alpha, module: :v1 do
      resources :accounts, only: [] do
        resources :collections, only: [:index]
      end
    end

    namespace :v1 do
      resources :trends, only: [:index], controller: 'trends/tags'
      namespace :trends do
        resources :tags, only: [:index]
      end
    end
  end

  namespace :admin do
    def keys_name = "keys"
    resources :api, only: [:index] do
      collection do
        resources :keys, controller: "api", only: %i[index update]
      end
    end
  end

  resources :posts, only: [:update, :destroy]
  patch "posts/:id/touch" => "posts#update"
end
