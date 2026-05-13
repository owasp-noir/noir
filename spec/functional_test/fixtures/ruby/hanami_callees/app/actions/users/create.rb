module Testapp
  module Actions
    module Users
      class Create < Testapp::Action
        params do
          required(:name).filled(:string)
          optional(:email).filled(:string)
        end

        def handle(request, response)
          payload = BuildUser.call(request.params[:source])
          created = UserService.create(payload)
          response.render serialize_user(created)
        end
      end
    end
  end
end
