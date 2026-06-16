require "http/server"

# heredoc protection test (fake route inside must be ignored by mask)
doc = <<-DOC
  Example code that must not produce endpoints:
    when "/heredoc-fake"
  get "/also-fake" do
  DOC

server = HTTP::Server.new do |context|
  case context.request.path
  when "/"
    context.response.content_type = "text/plain"
    context.response.print "home"
  when "/users"
    context.response.print "users list"
  when "/api/items"
    context.response.print "items"
  when "/after-heredoc"
    context.response.print "real after heredoc"
  end

  # combined method + path on one line (for explicit POST test)
  if context.request.method == "POST" && context.request.path == "/users"
    name = context.request.form_params["name"]?
    context.response.print "created #{name}"
  end

  # param accesses after the last route (attach via last_endpoint heuristic)
  page = context.request.query_params["page"]?
  token = context.request.headers["X-API-KEY"]?
  sess = context.request.cookies["session"]?
end

# Unrelated case (e.g. status/enum handling) that happens to contain a path-like literal.
# The analyzer's indent-tracked `case ...request.path` scope must ignore `when` here
# so we don't emit a false-positive endpoint for "/not-a-real-route".
status = "200"
case status
when "/not-a-real-route"
  puts "this must not become an endpoint"
end

address = server.bind_tcp(8080)
server.listen
