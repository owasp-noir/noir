require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/miniparsers/js_parser"

private def parsed(code : String, this_receiver_ok : Bool = true) : Array(String)
  Noir::JSParser.new(code, this_receiver_ok: this_receiver_ok).parse_routes.map { |r| "#{r.method} #{r.path}" }.uniq!
end

# Controllers that extend a local base class import no server, and apps are
# handed to a function as `http`: both look like outbound clients by name.
describe "JSParser route shapes in files without server evidence" do
  describe "this.<verb>(path, handler)" do
    it "keeps a method reference and a bare arrow handler" do
      {
        "class T extends Controller { constructor() { super(); this.get('/', this.getTags); } }"                 => "GET /",
        "class T extends Controller { constructor() { super(); this.post('/', this.createTag, ADMIN); } }"       => "POST /",
        "class T extends Controller { constructor() { super(); this.put('/:name', req => this.update(req)); } }" => "PUT /:name",
        "class T extends Controller { constructor() { super(); this.delete('/:n', async req => 1); } }"          => "DELETE /:n",
      }.each do |code, route|
        parsed(code, this_receiver_ok: false).should eq([route])
      end
    end

    it "drops client-class calls whose value is used or whose argument is not a method reference" do
      {
        "class P { go() { this.post('/orders',",
        "class P { go(body) { this.post('/orders', body,",
        "class P { go() { return this.post('/orders', this.payload); } }",
        "class P { go() { const r = await this.get('/x', this.defaults); } }",
        "class P { go(body) { this.post('/orders', body); } }",
        "class P { go(item) { this.put('/root/x', item.body, opts); } }",
        "class P { go(id) { this.get('/x', this.payload(id)); } }",
      }.each do |code|
        parsed(code, this_receiver_ok: false).should be_empty
      end
    end
  end

  describe "http / https / socket as an app parameter" do
    it "keeps a rooted route handed a handler" do
      {
        "module.exports = function registerRoutes(http) { http.get('/ping', handler); };"                   => "GET /ping",
        "module.exports = function registerRoutes(http) { http.post('/echo', auth, ctrl.echo); };"          => "POST /echo",
        "module.exports = function registerRoutes(https) { https.get('/p', (req, res) => res.end()); };"    => "GET /p",
        "module.exports = function registerRoutes(socket) { socket.get('/p', async (ctx) => ctx.body); };"  => "GET /p",
        "module.exports = function registerRoutes(http) { http.get('/p', function (request, reply) {}); };" => "GET /p",
      }.each do |code, route|
        parsed(code).should eq([route])
      end
    end

    it "still drops outbound client shapes" do
      {
        "http.get('http://localhost:3000/ping', (res) => { res.resume(); });",
        "https.get('https://example.com/x', function (err, res) {});",
        "http.get('/ping', (res) => { res.resume(); });",
        "http.post(`${BASE_URL}/auth/login/`, JSON.stringify(creds), params);",
        "http.post(`${BASE_URL}/auth/login/`, payload, params);",
        "http.get(`${BASE_URL}/public/`);",
        "socket.get('/users', { limit: 10 }, (data, jwr) => { render(data); });",
        "socket.post('/subscribe', payload, function (resData, jwr) {});",
        "const res = http.post('/api/x', payload);",
        "return await http.get('/api/x', cb);",
        "this.http.post('/api/users', user);",
        "this.http.get('/api/users', params);",
        "io.socket.post('/chat', message);",
      }.each do |code|
        parsed(code).should be_empty
      end
    end

    it "keeps a receiver the file builds from a server factory whatever the shape" do
      parsed("const express = require('express');\nconst http = express();\nhttp.get('/x', (res) => {});").should eq(["GET /x"])
    end
  end
end
