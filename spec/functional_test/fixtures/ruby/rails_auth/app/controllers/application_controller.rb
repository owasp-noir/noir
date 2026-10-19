class ApplicationController < ActionController::Base
  before_action :authenticate_user

  private

  # Decodes the token when one is sent and lets the request through when
  # none is: a token decoder, not a gate.
  def authenticate_user
    if request.headers['Authorization'].present?
      authenticate_or_request_with_http_token do |token|
        begin
          @current_user_id = JWT.decode(token, Rails.application.secrets.secret_key_base).first['id']
        rescue JWT::DecodeError
          head :unauthorized
        end
      end
    end
  end

  def authenticate_user!(options = {})
    head :unauthorized unless signed_in?
  end

  def signed_in?
    @current_user_id.present?
  end
end
