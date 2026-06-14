module MyAPI
  class Users < ::MyAPI::Base
    resource :users do
      get do
        present []
      end

      # route_param carrying a trailing `requirements:` kwarg before `do`.
      route_param :id, requirements: { id: /\d+/ } do
        get do
          present params[:id]
        end
      end
    end
  end
end
