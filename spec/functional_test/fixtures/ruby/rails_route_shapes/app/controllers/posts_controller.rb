class PostsController < ApplicationController
  def update
    Post.find(params[:id]).update!(raw: params[:raw])
  end

  def destroy
    Post.find(params[:id]).destroy!
  end
end
