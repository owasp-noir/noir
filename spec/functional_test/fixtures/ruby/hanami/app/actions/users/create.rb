module Testapp
  module Actions
    module Users
      class Create < Testapp::Action
        params do
          required(:username).filled(:string)
          required(:email).filled(:string)
          optional(:name).value(:string)
          optional(:age).maybe(:integer)
        end

        def handle(request, response)
          # Additional headers
          content_type = request.headers["Content-Type"]
          authorization = request.headers['Authorization']
        end
      end
    end
  end
end
