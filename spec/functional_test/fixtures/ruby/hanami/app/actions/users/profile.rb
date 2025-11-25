module Testapp
  module Actions
    module Users
      class Profile < Testapp::Action
        def handle(request, response)
          # Path parameter access using params
          user_id = params[:id]
          
          # Session cookies
          session_token = request.cookies["session_token"]
          
          # Headers with string keys
          if_none_match = request.headers["If-None-Match"]
        end
      end
    end
  end
end
