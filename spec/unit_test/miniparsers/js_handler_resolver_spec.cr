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
  it "resolves a package.json `imports` specifier, after tsconfig `paths`" do
    with_app do |dir, _|
      Dir.mkdir_p(File.join(dir, "src", "util", "title"))
      File.write(File.join(dir, "src", "util", "mw.ts"), "")
      File.write(File.join(dir, "src", "util", "title", "index.js"), "")
      File.write(File.join(dir, "package.json"), %({"imports": {"#util/*": "./src/util/*.ts", "#util/title": "./src/util/title/index.js", "#src/*": "./build/*", "#util/secret/*": null, "#mw": {"types": "./src/util/mw.d.ts", "node": "./src/util/mw.ts", "import": "./build/mw.js"}}}))
      from = File.join(dir, "server.ts")
      Noir::JSHandlerResolver.resolve_specifier(from, "#util/mw").should eq(File.join(dir, "src", "util", "mw.ts"))
      Noir::JSHandlerResolver.resolve_specifier(from, "#util/title").should eq(File.join(dir, "src", "util", "title", "index.js"))
      Noir::JSHandlerResolver.resolve_specifier(from, "#util/").should be_nil
      Noir::JSHandlerResolver.resolve_specifier(from, "#util/secret/mw").should be_nil
      # Conditions in the object's order, never `types`.
      Noir::JSHandlerResolver.resolve_specifier(from, "#mw").should eq(File.join(dir, "src", "util", "mw.ts"))
      # logto: package.json names the build output, tsconfig the source.
      Noir::JSHandlerResolver.resolve_specifier(from, "#src/util/mw").should be_nil
      File.write(File.join(dir, "tsconfig.json"), %({"compilerOptions": {"paths": {"#src/*": ["src/*"]}}}))
      Noir::JSHandlerResolver.reset
      Noir::JSHandlerResolver.resolve_specifier(from, "#src/util/mw").should eq(File.join(dir, "src", "util", "mw.ts"))
    end
  end

  it "is omitted from endpoint JSON when nil and round-trips when set" do
    ep = Endpoint.new("/x", "GET")
    ep.to_json.should_not contain("handler")
    ep.handler = Handler.new("show", "a.rb", 7)
    back = Endpoint.from_json(ep.to_json)
    back.handler.should eq(Handler.new("show", "a.rb", 7))
  end
end
