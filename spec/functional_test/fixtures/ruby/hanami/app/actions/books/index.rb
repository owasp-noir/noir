module Testapp
  module Actions
    module Books
      class Index < Testapp::Action
        def handle(request, response)
          # Query parameters
          page = request.params[:page]
          limit = request.params[:limit]
          
          # Headers
          api_key = request.headers['X-API-KEY']
        end
      end
    end
  end
end
