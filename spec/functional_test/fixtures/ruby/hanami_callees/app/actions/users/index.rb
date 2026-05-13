module Testapp
  module Actions
    module Users
      class Index < Testapp::Action
        def handle(request, response)
          page = request.params[:page]
          users = UserService.list(page)
          AuditLog.write("list")
          response.render serialize_users(users)
        end
      end
    end
  end
end
