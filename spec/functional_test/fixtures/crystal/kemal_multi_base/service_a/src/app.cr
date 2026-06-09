require "kemal"

public_folder "assets"

get "/a-only" do
  "a"
end
