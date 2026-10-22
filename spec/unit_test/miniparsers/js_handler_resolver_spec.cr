require "../../spec_helper"
require "file_utils"
require "../../../src/miniparsers/js_handler_resolver"

private def with_app(&)
  dir = File.tempname("noir-js-handler")
  Dir.mkdir_p(File.join(dir, "routes"))
  File.write(File.join(dir, "routes", "login.ts"), "import x from 'y'\n\nexport function login () {\n  return (req, res) => res.send(1)\n}\n")
  File.write(File.join(dir, "routes", "users.js"), "exports.list = (req, res) => {}\nexports.create = (req, res) => {}\n")
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "lib", "auth.ts"), "export const isAuthorized = () => (req, res, next) => next()\n")
  server = <<-JS
    import express from 'express'
    import axios from 'axios'
    import { login } from './routes/login'
    import * as security from './lib/auth'
    const users = require('./routes/users')
    const app = express()
    function local (req, res) { res.send('x') }
    JS
  File.write(File.join(dir, "server.ts"), server)
  CodeLocator.instance.scan_base_paths = [dir]
  Noir::JSHandlerResolver.reset
  yield dir, server
ensure
  CodeLocator.instance.scan_base_paths = [] of String
  FileUtils.rm_rf(dir) if dir
end

describe Noir::JSHandlerResolver do
  it "resolves a named import, a namespace member, a require and a local function to their definition lines" do
    with_app do |dir, server|
      path = File.join(dir, "server.ts")
      h = Noir::JSHandlerResolver.resolve("login()", server, path).not_nil!
      {h.name, h.path, h.line}.should eq({"login()", File.join(dir, "routes", "login.ts"), 3})

      h = Noir::JSHandlerResolver.resolve("security.isAuthorized()", server, path).not_nil!
      {h.path, h.line}.should eq({File.join(dir, "lib", "auth.ts"), 1})

      h = Noir::JSHandlerResolver.resolve("users.create", server, path).not_nil!
      {h.path, h.line}.should eq({File.join(dir, "routes", "users.js"), 2})

      h = Noir::JSHandlerResolver.resolve(" local ", server, path).not_nil!
      {h.name, h.path, h.line}.should eq({"local", path, 7})
    end
  end

  it "keeps the handler path relative when the route's path is relative" do
    with_app do |dir, server|
      Dir.cd(dir) do
        h = Noir::JSHandlerResolver.resolve("login()", server, "server.ts").not_nil!
        {h.path, h.line}.should eq({File.join("routes", "login.ts"), 3})
      end
    end
  end

  it "unwraps transparent async wrappers and reports no handler for middleware factories" do
    with_app do |dir, server|
      path = File.join(dir, "server.ts")
      h = Noir::JSHandlerResolver.resolve("utils.asyncHandler(login())", server, path).not_nil!
      {h.name, h.path, h.line}.should eq({"login()", File.join(dir, "routes", "login.ts"), 3})
      h = Noir::JSHandlerResolver.resolve("wrap(users.create)", server, path).not_nil!
      {h.name, h.line}.should eq({"users.create", 2})
      # `validate(schema)` is middleware around `schema`, not a wrapped handler.
      Noir::JSHandlerResolver.resolve("validate(login)", server, path).should be_nil
      Noir::JSHandlerResolver.resolve("cors()", server, path).should be_nil
      Noir::JSHandlerResolver.resolve("express.static", server, path).should be_nil
      Noir::JSHandlerResolver.resolve("bodyParser.json()", server, path).should be_nil
    end
  end

  it "returns nil for closures, calls with arguments, unknown members and package imports" do
    with_app do |dir, server|
      path = File.join(dir, "server.ts")
      Noir::JSHandlerResolver.resolve("(req, res) => res.send(1)", server, path).should be_nil
      Noir::JSHandlerResolver.resolve("utils.validate(login())", server, path).should be_nil
      Noir::JSHandlerResolver.resolve("nothing.here", server, path).should be_nil
      # `axios` is a package: the name is kept, nothing is resolved.
      h = Noir::JSHandlerResolver.resolve("axios.get", server, path).not_nil!
      {h.name, h.path, h.line}.should eq({"axios.get", nil, nil})
    end
  end
end

describe Handler do
  it "is omitted from endpoint JSON when nil and round-trips when set" do
    ep = Endpoint.new("/x", "GET")
    ep.to_json.should_not contain("handler")
    ep.handler = Handler.new("show", "a.rb", 7)
    back = Endpoint.from_json(ep.to_json)
    back.handler.should eq(Handler.new("show", "a.rb", 7))
  end
end
