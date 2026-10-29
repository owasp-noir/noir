class PostsController < ApplicationController
  def update
    Post.find(params[:id]).update!(raw: params[:raw])
  end
end
