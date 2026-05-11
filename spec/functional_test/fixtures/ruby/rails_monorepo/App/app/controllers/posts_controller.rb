class PostsController < ApplicationController
  def index
    @posts = Post.all
  end

  def show
    request.headers['X-API-KEY']
  end

  def create
    @post = Post.new(post_params)
    render json: @post
  end

  def update
  end

  def destroy
  end

  private

  def post_params
    params.require(:post).permit(:title, :context)
  end
end
