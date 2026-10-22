require "kemal"

get "/one" do |env|
  env.params.query["q1"]
  env.request.headers["X-H1"]
end

post "/split" do |env|
  env.params.query[
    "q2",
  ]
  env.params.body[
    "f2",
  ]
  env.request.headers[
    "X-H2",
  ]
  env.params.json[
    "j2",
  ]
  env.request.cookies[
    "c2",
  ]
end

Kemal.run
