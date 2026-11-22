require "../../spec_helper"
require "../../../src/miniparsers/express_middleware"

describe Noir::ExpressMiddleware do
  it "indexes bindings only when a route can inherit an earlier registration" do
    file = File.expand_path("routes.js")
    source = <<-JS
      function left(router) { router.use(auth); router.get('/left', show); }
      function right(router) { router.get('/right', show); }
      JS
    reads = [] of String
    middleware = Noir::ExpressMiddleware.new do |path|
      reads << path
      source
    end
    middleware.register(Noir::ExpressMiddleware::Use.new(File.expand_path("client.js"), "client", 0, nil, ["plugin"]))
    middleware.register(Noir::ExpressMiddleware::Use.new(file, "router", source.index!("use"), nil, ["auth"]))
    middleware.finish

    chain = ->(receiver : String, at : Int32) do
      middleware.chain(file, receiver, at, "", "", [] of String, "/leaf", ["show"]).map(&.source)
    end
    chain.call("app", source.size).should eq ["show"]
    chain.call("router", 0).should eq ["show"]
    reads.should be_empty
    chain.call("router", source.index!("/left")).should eq ["auth", "show"]
    chain.call("router", source.index!("/right")).should eq ["show"]
    reads.should eq [file]
  end
end
