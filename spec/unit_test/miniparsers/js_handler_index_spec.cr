require "../../spec_helper"
require "../../../src/miniparsers/js_handler_resolver"

describe "JavaScript local handler index" do
  before_each { Noir::JSHandlerResolver.reset }
  after_each { Noir::JSHandlerResolver.reset }

  it "keeps definition lines, generators, generic names and first-match priority" do
    source = <<-TS
      // café
      export async function* stream<T>() { yield 1; }

      function $handler() {}
      function $handler() {}
      exports.$handler = () => {};
      TS
    Noir::JSHandlerResolver.resolve("stream", source, "routes.ts").not_nil!.line.should eq(2)
    Noir::JSHandlerResolver.resolve("$handler", source, "routes.ts").not_nil!.line.should eq(4)
  end

  it "keeps the fallback for arrow handlers and unbound names" do
    source = "function declared() {}\nconst arrow = (req, res) => res.send('ok');\n"
    Noir::JSHandlerResolver.resolve("declared", source, "routes.js").not_nil!.line.should eq(1)
    Noir::JSHandlerResolver.resolve("arrow", source, "routes.js").not_nil!.line.should eq(2)
    Noir::JSHandlerResolver.resolve("absent", source, "routes.js").should be_nil
  end

  it "does not reuse another source buffer's indexed lines" do
    old = "function first() {}\nfunction second() {}\n"
    fresh = "// changed\n\nfunction second() {}\n"
    Noir::JSHandlerResolver.resolve("first", old, "routes.js").not_nil!.line.should eq(1)
    Noir::JSHandlerResolver.resolve("second", fresh, "routes.js").not_nil!.line.should eq(3)
  end

  it "avoids allocating a source prefix per named handler" do
    n = 4000
    source = String.build do |io|
      n.times { |i| io << "function h#{i}(req,res) { return res.json({ok:true}); }\n" }
    end
    GC.collect
    allocated = GC.stats.total_bytes
    n.times do |i|
      handler = Noir::JSHandlerResolver.resolve("h#{i}", source, "routes.js").not_nil!
      handler.line.should eq(i + 1)
    end
    # The per-name regex scans and copied prefixes allocated ~456 MB.
    (GC.stats.total_bytes - allocated).should be < 64 * 1024 * 1024
  end
end
