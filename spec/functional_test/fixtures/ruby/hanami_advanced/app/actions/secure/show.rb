module Testapp
  module Actions
    module Secure
      class Show < Testapp::Action
        plug :authenticate

        def handle(request, response)
          response.render SecureRenderer.render
        end

        private

        def authenticate(request, response)
          TokenVerifier.verify(request.headers["Authorization"])
        end
      end
    end
  end
end
