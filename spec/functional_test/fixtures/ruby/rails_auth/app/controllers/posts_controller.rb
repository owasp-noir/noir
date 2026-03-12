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
    post = Post.new(params.permit(:title, :body))
    authorize post
    render json: post.save
  end

  def destroy
    render json: Post.find(params[:id]).destroy
  end
end
