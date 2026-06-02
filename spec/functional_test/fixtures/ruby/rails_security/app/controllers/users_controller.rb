class UsersController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token, only: [:create]

  def index
    render json: User.all
  end

  def create
    user = User.new(params[:user])
    user.save
    render json: user
  end

  def update
    user = User.find(params[:id])
    user.update(params.permit!)
    render json: user
  end
end
