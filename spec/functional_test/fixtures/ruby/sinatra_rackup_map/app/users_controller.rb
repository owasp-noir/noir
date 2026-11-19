require "sinatra/base"
class UsersController < Sinatra::Base
  get "/" do
    "list"
  end
  get "/:id" do
    params[:id]
  end
end
