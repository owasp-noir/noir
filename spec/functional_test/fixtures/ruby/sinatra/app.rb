require 'sinatra'

# Regression guard: route DSL inside an RDoc-style comment block is
# documentation, not a registration. Neither URL should surface as
# an endpoint.
#
#     get "/should-not-appear-doc" do
#       erb :index
#     end
#
#     post "/should-not-appear-doc-post" do
#       :ok
#     end

# Regression guard: `headers.delete '...'` is a method call on a
# response-headers hash, NOT a DELETE route registration. The shared
# `line_to_endpoint` rejects verb shapes preceded by `.` or word chars.
class HeaderShim
  def reset(headers)
    headers.delete 'content-length'
    headers.delete 'content-type'
  end
end

get '/' do
  puts param['query']
  puts cookies[:cookie1]
  puts cookies["cookie2"]
end

post "/update" do
  puts "update"
end

namespace "/api" do
  get "/widgets" do
    params[:page]
  end

  post("/widgets") do
    request.env["HTTP_X_TRACE_ID"]
  end
end
