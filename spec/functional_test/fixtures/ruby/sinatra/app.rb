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

# Regression guard: the verb words double as ordinary Ruby methods. A
# Rails+Sinatra app runs these in migrations / service objects that the
# Sinatra analyzer also scans. The string argument is not a rooted route
# path, so none may surface as an endpoint (the old matcher turned the
# raw SQL into a phantom `DELETE /DELETE FROM ...`, and a non-rooted
# Rails route `get "release-notes"` leaked without its real scope).
class Maintenance
  def run
    delete "DELETE FROM articles WHERE archived = true"
    post "https://hooks.example.com/notify"
    get "release-notes"
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

  route :get, :post, "/route_widgets" do
    params.fetch(:token)
  end

  route :get, "/verb_named/:post" do
    params[:id]
  end
end

namespace "/v2" {
  get "/widgets" do
    params.fetch("cursor")
  end
}

# Regression guard: a multi-line `if`/`else`/`end` inside a route body
# must not corrupt namespace depth tracking. With the old open/close
# tally the `if`'s `end` over-decremented depth, popping the `/admin`
# prefix so `/admin/audit` leaked out as `/audit`.
namespace "/admin" do
  get "/dashboard" do
    if params[:full]
      erb :full_dashboard
    else
      erb :dashboard
    end
  end

  get "/audit" do
    params[:since]
  end
end
get "/files/*" do
  params[:splat]
  params[:real]
end

def helper_noise
  params[:should_not_attach]
  request.env["HTTP_SHOULD_NOT_ATTACH"]
end
