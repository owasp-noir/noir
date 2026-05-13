module Testapp
  module Actions
    module Health
      class Ready < Testapp::Action
        def handle(request, response) = response.render(HealthCheck.ready)
      end
    end
  end
end
