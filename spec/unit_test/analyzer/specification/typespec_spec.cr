require "file_utils"
require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/specification/typespec"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"

describe "TypeSpec analyzer on non-ASCII content" do
  after_each { CodeLocator.instance.clear_all }

  # One Korean character made `String#[](Int)` O(index), so the comment
  # stripper and the walker went quadratic: 1200 operations took ~2 minutes.
  it "stays linear and keeps non-ASCII routes intact" do
    dir = File.tempname("noir_typespec_utf8")
    Dir.mkdir_p(dir)
    begin
      ops = (0...1200).map { |i| %(  @route("/r#{i}/{id}") @get op get#{i}(@path id: string, @query q#{i}: string): void;) }
      entry = File.join(dir, "main.tsp")
      File.write(entry, "// 한국어 주석\nnamespace Demo {\n#{ops.join("\n")}\n  /* 블록 */\n  @route(\"/명령\") @post op make(@body b: string): void;\n}\n")

      CodeLocator.instance.clear_all
      CodeLocator.instance.push(Noir::LocatorKeys::TYPESPEC_SPEC, entry)

      endpoints = [] of Endpoint
      elapsed = Time.measure do
        endpoints = Analyzer::Specification::TypeSpec.new(create_test_options).analyze
      end

      endpoints.size.should eq(1201)
      endpoints.find! { |e| e.url == "/r7/{id}" }.params.map(&.name).should eq(["id", "q7"])
      endpoints.find! { |e| e.url == "/명령" }.method.should eq("POST")
      elapsed.should be < 5.seconds
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
