require 'webrick'

# Minimal pure-stdlib WEBrick example (no Gemfile dependency).
server = WEBrick::HTTPServer.new(Port: 8080)

# Plain mount_proc - defaults to GET in analyzer
server.mount_proc '/' do |req, res|
  res.body = 'root'
end

# mount_proc with method dispatch + query + body + header + cookie params
server.mount_proc '/api/users' do |req, res|
  case req.request_method
  when 'GET'
    page = req.query['page']
    limit = req.query["limit"]
    # comment fake must be ignored: # req.query['fake_comment']
  when 'POST'
    # WEBrick idiom for form body
    body_params = WEBrick::HTTPUtils.parse_query(req.body.to_s)
    name = body_params['name']
    # header access (both styles)
    token = req['X-Token']
    auth = req.header['authorization']
    # cookie
    sess = req.cookies.find { |c| c.name == 'session' }
    # json body example
    if (ct = req['Content-Type']) && ct.to_s.include?('json')
      begin
        payload = JSON.parse(req.body.to_s)
        uid = payload['id']
      rescue
      end
    end
  end
end

# Simple unconditional GET
server.mount_proc '/health' do |req, res|
  if req.request_method == "GET"
    res.body = 'ok'
  end
end

# Servlet example (class-based, multi-method)
class ApiServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    # path param simulation via query in real code often
    id = req.query["id"]
    # header via bracket + header hash
    token = req["X-Auth"] || (req.header["x-auth"] ? req.header["x-auth"].first : nil)
    res.body = "item-#{id}"
  end

  def do_DELETE(req, res)
    id = req.query['id']
    res.status = 204
  end
end

server.mount '/api/items', ApiServlet

# Static must be ignored by analyzer
server.mount '/static', WEBrick::HTTPServlet::FileHandler, '/var/www'

# Fake in comment - must not produce phantom endpoint
# server.mount_proc '/comment-fake' do |req, res| end
# if req.path == "/also-fake"

trap 'INT' do server.shutdown end
server.start
