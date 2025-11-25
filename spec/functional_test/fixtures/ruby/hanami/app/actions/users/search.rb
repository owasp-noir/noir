module Testapp
  module Actions
    module Users
      class Search < Testapp::Action
        def handle(request, response)
          # Query parameters with different patterns
          query = params[:query]
          page = params[:page]
          limit = request.params[:limit]
          
          # String key patterns
          sort = params["sort"]
          order = request.params["order"]
          
          # Environment headers
          user_agent = request.env['HTTP_USER_AGENT']
          custom_header = request.env['HTTP_X_CUSTOM']
        end
      end
    end
  end
end
