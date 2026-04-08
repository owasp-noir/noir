require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/miniparsers/js_route_extractor"

describe Noir::JSRouteExtractor do
  describe "normalize_http_method" do
    it "normalizes DEL to DELETE" do
      Noir::JSRouteExtractor.normalize_http_method("DEL").should eq("DELETE")
      Noir::JSRouteExtractor.normalize_http_method("del").should eq("DELETE")
    end

    it "keeps standard methods unchanged" do
      Noir::JSRouteExtractor.normalize_http_method("GET").should eq("GET")
      Noir::JSRouteExtractor.normalize_http_method("POST").should eq("POST")
      Noir::JSRouteExtractor.normalize_http_method("PUT").should eq("PUT")
      Noir::JSRouteExtractor.normalize_http_method("DELETE").should eq("DELETE")
      Noir::JSRouteExtractor.normalize_http_method("PATCH").should eq("PATCH")
      Noir::JSRouteExtractor.normalize_http_method("HEAD").should eq("HEAD")
    end

    it "uppercases methods" do
      Noir::JSRouteExtractor.normalize_http_method("get").should eq("GET")
      Noir::JSRouteExtractor.normalize_http_method("post").should eq("POST")
    end

    it "keeps ALL as ALL" do
      Noir::JSRouteExtractor.normalize_http_method("ALL").should eq("ALL")
      Noir::JSRouteExtractor.normalize_http_method("all").should eq("ALL")
    end

    it "keeps OPTIONS" do
      Noir::JSRouteExtractor.normalize_http_method("OPTIONS").should eq("OPTIONS")
    end

    it "returns uppercased unknown methods" do
      Noir::JSRouteExtractor.normalize_http_method("custom").should eq("CUSTOM")
    end
  end

  describe "extract_body_params" do
    it "extracts destructured body params" do
      handler = "{ const { name, email } = req.body; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "name" && p.param_type == "json" }.should be_true
      endpoint.params.any? { |p| p.name == "email" && p.param_type == "json" }.should be_true
    end

    it "extracts direct property access body params" do
      handler = "{ const name = req.body.username; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "username" && p.param_type == "json" }.should be_true
    end

    it "extracts bracket notation body params" do
      handler = "{ const val = req.body['token']; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "token" && p.param_type == "json" }.should be_true
    end

    it "extracts Hono-style json body params" do
      handler = "{ const { name, age } = await c.req.json(); }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "name" && p.param_type == "json" }.should be_true
      endpoint.params.any? { |p| p.name == "age" && p.param_type == "json" }.should be_true
    end

    it "extracts Hono-style parseBody form params" do
      handler = "{ const { file, description } = await c.req.parseBody(); }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "file" && p.param_type == "form" }.should be_true
      endpoint.params.any? { |p| p.name == "description" && p.param_type == "form" }.should be_true
    end
  end

  describe "extract_query_params" do
    it "extracts destructured query params" do
      handler = "{ const { page, limit } = req.query; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "page" && p.param_type == "query" }.should be_true
      endpoint.params.any? { |p| p.name == "limit" && p.param_type == "query" }.should be_true
    end

    it "extracts direct query property access" do
      handler = "{ const p = req.query.search; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
    end

    it "extracts Hono-style query params" do
      handler = "{ const q = c.req.query('search'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
    end

    it "extracts Hono-style queries params" do
      handler = "{ const tags = c.req.queries('tag'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "tag" && p.param_type == "query" }.should be_true
    end
  end

  describe "extract_header_params" do
    it "extracts bracket notation header params" do
      handler = "{ const auth = req.headers['authorization']; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "authorization" && p.param_type == "header" }.should be_true
    end

    it "extracts dot notation header params" do
      handler = "{ const ct = req.headers.host; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "host" && p.param_type == "header" }.should be_true
    end

    it "extracts Express-style req.header() params" do
      handler = "{ const ct = req.header('Content-Type'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "Content-Type" && p.param_type == "header" }.should be_true
    end

    it "extracts Koa-style ctx.get() header params" do
      handler = "{ const auth = ctx.get('Authorization'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "Authorization" && p.param_type == "header" }.should be_true
    end

    it "extracts Hono-style header params" do
      handler = "{ const token = c.req.header('X-API-Key'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "X-API-Key" && p.param_type == "header" }.should be_true
    end
  end

  describe "extract_cookie_params" do
    it "extracts Express-style cookie params" do
      handler = "{ const sid = req.cookies.session_id; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "session_id" && p.param_type == "cookie" }.should be_true
    end

    it "extracts Koa-style cookie params" do
      handler = "{ const token = ctx.cookies.get('session'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "session" && p.param_type == "cookie" }.should be_true
    end

    it "extracts Hono-style getCookie params" do
      handler = "{ const val = getCookie(c, 'auth_token'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "auth_token" && p.param_type == "cookie" }.should be_true
    end
  end

  describe "extract_path_params" do
    it "extracts Express-style path params with dot notation" do
      handler = "{ const id = req.params.id; }"
      endpoint = Endpoint.new("/test/:id", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    end

    it "extracts bracket notation path params" do
      handler = "{ const id = req.params['userId']; }"
      endpoint = Endpoint.new("/test/:userId", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "userId" && p.param_type == "path" }.should be_true
    end

    it "extracts Hono-style path params" do
      handler = "{ const id = c.req.param('id'); }"
      endpoint = Endpoint.new("/test/:id", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    end

    it "extracts Koa-style path params" do
      handler = "{ const id = ctx.params.id; }"
      endpoint = Endpoint.new("/test/:id", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    end

    it "does not duplicate existing path params" do
      handler = "{ const id = req.params.id; }"
      endpoint = Endpoint.new("/test/:id", "GET")
      endpoint.push_param(Param.new("id", "", "path"))
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      path_params = endpoint.params.select { |p| p.name == "id" && p.param_type == "path" }
      path_params.size.should eq(1)
    end
  end

  describe "extract_static_paths" do
    it "extracts Express static with prefix" do
      content = "app.use('/static', express.static('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/static" && p["file_path"] == "public" }.should be_true
    end

    it "extracts Express static without prefix" do
      content = "app.use(express.static('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/" && p["file_path"] == "public" }.should be_true
    end

    it "extracts Koa-style serve" do
      content = "app.use(serve('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/" && p["file_path"] == "public" }.should be_true
    end

    it "extracts Koa mount + serve" do
      content = "app.use(mount('/assets', serve('static')))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/assets" && p["file_path"] == "static" }.should be_true
    end

    it "returns empty for no static paths" do
      content = "app.get('/users', handler);"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.size.should eq(0)
    end
  end

  describe "extract_routes" do
    it "returns empty for non-existent file" do
      routes = Noir::JSRouteExtractor.extract_routes("/nonexistent/file.js")
      routes.size.should eq(0)
    end
  end
end
