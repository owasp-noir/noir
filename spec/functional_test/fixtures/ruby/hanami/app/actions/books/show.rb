module Testapp
  module Actions
    module Books
      class Show < Testapp::Action
        def handle(request, response)
          # Headers
          authorization = request.headers['Authorization']
          
          # Cookies
          session_id = request.cookies['session_id']
        end
      end
    end
  end
end
