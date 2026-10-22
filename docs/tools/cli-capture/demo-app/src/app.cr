# A deliberately small Kemal app whose scan output is the CLI screenshot in
# the docs (see docs/tools/cli-capture/). Every route is here to put one
# specific thing on screen: a header, a cookie, a websocket route, and body
# params that earn a tag. Keep it boring and stable: every change here
# changes published images.
#
# The tagged params are the fragile part. They earn their tags by appearing
# verbatim in a word list in src/tagger/taggers/hunt_param.cr ("search" is in
# the sqli list, "redirect_url" in ssrf, "client_id" and "grant_type" in
# oauth), so renaming one to something that reads better silently drops its
# tag from the screenshot. Check that file before touching them.
require "kemal"

get "/" do |env|
  env.request.headers["x-api-key"]
  "Welcome!"
end

post "/search" do |env|
  env.request.cookies["my_auth"]
  env.params.body["search"]
end

get "/token" do |env|
  env.params.body["client_id"]
  env.params.body["redirect_url"]
  env.params.body["grant_type"]
end

ws "/socket" do |socket|
  socket.send "Hello from the demo app!"
end

Kemal.run
