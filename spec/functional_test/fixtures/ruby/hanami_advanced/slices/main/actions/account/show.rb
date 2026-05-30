module Main
  module Actions
    module Account
      class Show < Main::Action
        def handle(request, response)
          response.render actor(request).account
        end
      end
    end
  end
end
