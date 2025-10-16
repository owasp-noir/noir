module Testapp
  module Actions
    module Books
      class Create < Testapp::Action
        params do
          required(:title).filled(:string)
          required(:author).filled(:string)
          optional(:isbn).filled(:string)
        end

        def handle(request, response)
          # Headers
          content_type = request.headers['Content-Type']
          
          # Cookies
          user_token = request.cookies['user_token']
        end
      end
    end
  end
end
