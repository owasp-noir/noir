require "kemal"
require "./routes/misc"

get "/a", Routes::Misc, :home

Kemal.run
