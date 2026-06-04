require "grape"

class API < Grape::API
  version "v1", using: :header, vendor: "twitter"
  format :json

  resource :users do
    desc "Return list of users"
    get do
      User.all
    end

    desc "Return a user"
    params do
      requires :id, type: Integer
    end
    get ":id" do
      User.find(params[:id])
    end

    post do
      User.create!(params[:name])
    end

    put ":id" do
      User.find(params[:id]).update!(params)
    end

    delete ":id" do
      User.find(params[:id]).destroy
    end
  end

  namespace :orders do
    get do
    end

    post do
    end
  end

  resource :accounts do
    route_param :account_id do
      get "profile" do
        params[:expand]
      end
    end
  end

  resource :articles do
    # `requires :title` declares a json body param.
    params do
      requires :title
    end
    post do
      token_header = "X-Token"
      headers[token_header]   # bare variable subscript — must NOT become a param
      headers["X-Request-Id"] # string literal — surfaces as a header param
      params[:title]          # already declared json — must NOT re-add as query
    end
  end

  version "v2", using: :path

  resource :status do
    get do
    end

    # Symbol path is a LITERAL segment: `get :ping` => /v2/status/ping,
    # not the bogus param route /v2/status/{ping}.
    get :ping do
      {pong: true}
    end
  end

  # Auth examples for grape_auth tagger testing
  before { authenticate! }

  resource :admin do
    before { require_admin! }
    get "dashboard" do
      {ok: true}
    end
  end

  http_basic do |username, password|
    # basic auth example
  end

  get "secret" do
    error!('Unauthorized', 401) unless current_user
    {secret: true}
  end

  helpers do
    def authenticate!
      # ...
    end

    def require_admin!
      # ...
    end

    def current_user
      # ...
    end
  end
end
