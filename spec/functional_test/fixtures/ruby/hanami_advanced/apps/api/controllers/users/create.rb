module Api
  module Controllers
    module Users
      class Create
        include Api::Action

        params do
          required(:user).schema do
            required(:username).filled
          end
        end

        def call(params)
          UserRepository.create(params.get(:user, :username))
        end
      end
    end
  end
end
