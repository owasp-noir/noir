module Shop
  module Api
    module V3
      class AuthController < ActionController::API
        before_action :authenticate_user!

        def create
          render json: User.find_by(email: params[:email])
        end
      end
    end
  end
end
