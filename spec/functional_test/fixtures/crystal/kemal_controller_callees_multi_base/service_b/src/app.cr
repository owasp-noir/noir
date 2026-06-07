require "kemal"
require "./routes/misc"

get "/b", Routes::Misc, :home

Kemal.run
