class PostsController < ApplicationController
  def show
    Post.find(params[:id])
  end
end
