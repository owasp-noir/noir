module Testapp
  module Actions
    module Users
      class Destroy < Testapp::Action
        def handle(request, response); UserService.delete(id); response.status = 204; end
      end
    end
  end
end
