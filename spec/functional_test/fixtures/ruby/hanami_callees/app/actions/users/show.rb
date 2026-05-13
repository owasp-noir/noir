module Testapp
  module Actions
    module Users
      class Show < Testapp::Action
        def handle(request, response)
          user = if Feature.enabled?
            UserService.find(id)
          else
            UserFallback.find(id)
          end
          response.render serialize_user(user)
        end
      end
    end
  end
end
