require "sinatra/base"
class HomeController < Sinatra::Base
  get "/" do
    "home"
  end
end
