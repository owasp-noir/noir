class SessionsController < Devise::SessionsController
  def create
    user = User.find_by_email(sign_in_params[:email])
    render json: { errors: ['invalid'] }, status: :unprocessable_entity unless user
  end
end
