class PostsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :authenticate_user!, only: [:index]

  def index
    render json: Post.all
  end

  def show
    render json: Post.find(params[:id])
  end

  def create
    authorize @post
    render json: Post.create(post_params)
  end

  def destroy
    render json: Post.find(params[:id]).destroy
  end
end
