module Testapp
  module Actions
    module Books
      class Update < Testapp::Action
        params do
          required(:title).filled(:string)
          optional(:author).filled(:string)
        end

        def handle(request, response)
          # Headers
          if_match = request.headers['If-Match']
        end
      end
    end
  end
end
