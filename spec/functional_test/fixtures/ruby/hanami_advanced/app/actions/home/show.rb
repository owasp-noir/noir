module Testapp
  module Actions
    module Home
      class Show < Testapp::Action
        def handle(request, response)
          response.render HomePage.render
        end
      end
    end
  end
end
