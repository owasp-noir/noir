class PostsController < ApplicationController
  def index
    render json: Post.all
  end

  def create
    post = Post.new(post_params)
    post.save
    render json: post
  end

  private

  def post_params
    params.require(:post).permit(:title, :body)
  end
end
