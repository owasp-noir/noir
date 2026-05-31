module Api
  module Controllers
    module Users
      class Login
        include Api::Action

        def call(params)
          Authenticator.login(params.get(:email), params.get(:password))
        end
      end
    end
  end
end
