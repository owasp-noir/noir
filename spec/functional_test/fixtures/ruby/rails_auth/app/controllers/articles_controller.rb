class ArticlesController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]

  def index
    render json: Article.all
  end

  def show
    render json: Article.find(params[:id])
  end

  def feed
    render json: Article.where(user: current_user.following_users)
  end
end
