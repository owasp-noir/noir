require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/rust/actix_web"

# Walkers that recurse *outside* an `each_named_child` block — on a
# `field(...)` receiver, or on a child array materialised up front so the
# walk can look ahead — are invisible to the shared depth guard in
# `Noir::TreeSitter.each_named_child` and carry their own `depth`
# parameter instead. These specs pin that: the assertion is just "returns
# without crashing", because a stack overflow is a hard process abort that
# no `rescue` upstream can turn into a per-file failure.
private NEST = 6000

private def with_rust_file(content : String, &)
  dir = File.tempname("deep_nesting_spec")
  Dir.mkdir_p(dir)
  path = File.join(dir, "main.rs")
  File.write(path, content)
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
    Dir.delete(dir) if Dir.exists?(dir)
  end
end

describe "deeply nested Rust sources" do
  options = create_test_options

  it "survives a #{NEST}-link .service() chain (receiver recursion)" do
    source = String.build do |io|
      io << "use actix_web::{web, App};\n\nfn app() {\n    App::new()"
      NEST.times { io << ".service(h)" }
      io << ";\n}\n"
    end

    with_rust_file(source) do |path|
      Analyzer::Rust::ActixWeb.new(options).analyze_file(path)
    end
  end

  it "survives #{NEST} nested blocks (attribute/function pair walk)" do
    source = String.build do |io|
      io << "fn deep() {\n"
      NEST.times { io << "if a {\n" }
      NEST.times { io << "}\n" }
      io << "}\n"
    end

    with_rust_file(source) do |path|
      Analyzer::Rust::ActixWeb.new(options).analyze_file(path)
    end
  end
end
