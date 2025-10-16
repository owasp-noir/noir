module Testapp
  module Actions
    module Books
      class Destroy < Testapp::Action
        def handle(request, response)
          # Cookies
          csrf_token = request.cookies['csrf_token']
        end
      end
    end
  end
end
