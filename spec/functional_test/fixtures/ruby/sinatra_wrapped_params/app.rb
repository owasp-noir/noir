require 'sinatra'

get "/one" do
  params[:q1]
  request.env["HTTP_X_H1"]
end

get "/split" do
  params.fetch(
    :q2
  )
  params[
    "q3"
  ]
  request.env[
    "HTTP_X_H2"
  ]
  cookies[
    :c2
  ]
  # params.fetch(
  #   :ghost
  # )
end
