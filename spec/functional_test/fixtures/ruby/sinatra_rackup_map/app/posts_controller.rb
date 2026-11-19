require "sinatra/base"
class PostsController < Sinatra::Base
  get "/:id" do
    params[:id]
  end
end
