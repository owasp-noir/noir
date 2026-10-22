require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/rust/warp"

describe Analyzer::Rust::Warp do
  options = create_test_options

  # The calls chained after each `.or` apply to every alternative before
  # it. They are collected once per split and shared; re-walking them per
  # alternative took ~23s here.
  it "splits a 4000-alternative .or().unify().and(header) chain in linear time" do
    source = String.build do |io|
      io << "use warp::Filter;\n\nfn routes() -> impl Filter<Extract = impl warp::Reply, Error = warp::Rejection> + Clone {\n    warp::path(\"p0\")"
      (1...4000).each { |i| io << ".or(warp::path(\"p#{i}\")).unify().and(warp::header::<String>(\"h\"))" }
      io << "\n}\n"
    end

    temp_dir = File.tempname("warp_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "main.rs")
    File.write(temp_file, source)
    begin
      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Rust::Warp.new(options).analyze_file(temp_file) }

      endpoints.size.should eq(4000)
      endpoints.first.url.should eq("/p0")
      endpoints.first.params.map { |p| "#{p.param_type}:#{p.name}" }.should eq(["header:h"])
      endpoints.last.url.should eq("/p3999")
      elapsed.should be < 5.seconds
    ensure
      File.delete(temp_file)
      Dir.delete(temp_dir)
    end
  end
end
