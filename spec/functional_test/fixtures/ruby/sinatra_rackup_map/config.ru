require_relative "app/home_controller"
require_relative "app/users_controller"
require_relative "app/posts_controller"

map('/users') { run UsersController }
map "/posts" do
  run PostsController
end
map('/') { run HomeController }
