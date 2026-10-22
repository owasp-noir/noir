class ClientsController < ApplicationController
  skip_before_action :authenticate_user, except: [:show]
  before_action :track_client, only: [:index]

  def index
    render json: Client.all
  end

  def show
    render json: Client.find(params[:id])
  end

  private

  def track_client
    @client_id = request.env['HTTP_X_CLIENT_ID']
    @version = request.headers.fetch('X-Api-Version', '1')
    @hint = cookies.signed[:session_hint]
  end
end
