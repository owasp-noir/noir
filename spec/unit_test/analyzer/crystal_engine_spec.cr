require "../../spec_helper"
require "../../../src/analyzer/engines/crystal_engine"

class CrystalEngineSpecHarness < Analyzer::Crystal::CrystalEngine
  def analyze_file(path : String) : Array(Endpoint)
    [] of Endpoint
  end

  def test_normalize_crystal_interpolation(path : String) : String
    normalize_crystal_interpolation(path)
  end

  def test_crystal_do_block_open_delta(line : String) : Int32
    crystal_do_block_open_delta(line)
  end

  def test_extract_crystal_do_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
    extract_crystal_do_block(lines, start_index)
  end

  def test_extract_crystal_def_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
    extract_crystal_def_block(lines, start_index)
  end

  def test_valid_crystal_route_path?(path : String) : Bool
    valid_crystal_route_path?(path)
  end

  def test_collect_actions(lines : Array(String), path : String) : ActionIndex
    index = ActionIndex.new
    collect_actions_into(index, lines, path)
    index
  end

  def test_resolve_action_callees(index : ActionIndex, controller : String, action : String)
    resolve_action_callees(index, controller, action)
  end

  def test_crystal_dependency_path?(path : String) : Bool
    crystal_dependency_path?(path)
  end
end

describe Analyzer::Crystal::CrystalEngine do
  harness = CrystalEngineSpecHarness.new(create_test_options)

  describe "#normalize_crystal_interpolation" do
    it "replaces Crystal style interpolation with curly braces" do
      harness.test_normalize_crystal_interpolation("/api/\#{VERSION}/items").should eq("/api/{VERSION}/items")
      harness.test_normalize_crystal_interpolation("/users/\#{id}").should eq("/users/{id}")
    end

    it "handles no interpolation gracefully" do
      harness.test_normalize_crystal_interpolation("/api/v1/items").should eq("/api/v1/items")
    end
  end

  describe "#crystal_do_block_open_delta" do
    it "detects do block start" do
      harness.test_crystal_do_block_open_delta("get \"/\" do").should eq(1)
      harness.test_crystal_do_block_open_delta("get \"/\" do |req|").should eq(1)
    end

    it "returns 0 for do block that is closed on the same line" do
      harness.test_crystal_do_block_open_delta("get \"/\" do; end").should eq(0)
    end

    it "detects structural keywords like if, def, class, module" do
      harness.test_crystal_do_block_open_delta("if true").should eq(1)
      harness.test_crystal_do_block_open_delta("def hello").should eq(1)
      harness.test_crystal_do_block_open_delta("class User").should eq(1)
    end
  end

  describe "#extract_crystal_do_block" do
    it "extracts multiline do block successfully" do
      lines = [
        "get \"/\" do",
        "  x = 1",
        "  y = 2",
        "end",
      ]
      res = harness.test_extract_crystal_do_block(lines, 0)
      res.should_not be_nil
      if res
        body, start_line = res
        body.should eq("  x = 1\n  y = 2")
        start_line.should eq(2)
      end
    end

    it "handles nested blocks correctly" do
      lines = [
        "get \"/\" do",
        "  if x",
        "    y = 2",
        "  end",
        "end",
      ]
      res = harness.test_extract_crystal_do_block(lines, 0)
      res.should_not be_nil
      if res
        body, start_line = res
        body.should eq("  if x\n    y = 2\n  end")
        start_line.should eq(2)
      end
    end
  end

  describe "#extract_crystal_def_block" do
    it "extracts multiline def block successfully" do
      lines = [
        "def test_func",
        "  a = \"hello\"",
        "  b = \"world\"",
        "end",
      ]
      res = harness.test_extract_crystal_def_block(lines, 0)
      res.should_not be_nil
      if res
        body, start_line = res
        body.should eq("  a = \"hello\"\n  b = \"world\"")
        start_line.should eq(2)
      end
    end
  end

  describe "#valid_crystal_route_path?" do
    it "accepts genuine route paths (root, params, glob, interpolation)" do
      harness.test_valid_crystal_route_path?("/").should be_true
      harness.test_valid_crystal_route_path?("/users/:id").should be_true
      harness.test_valid_crystal_route_path?("/posts/*").should be_true
      harness.test_valid_crystal_route_path?("{VERSION}/items").should be_true
    end

    it "rejects captures from string args and prose" do
      # `method: "get", template: "…"`, `nested_arrays("post")`, the word
      # "post" in a sentence — all surface as non-path captures.
      harness.test_valid_crystal_route_path?(", template:").should be_false
      harness.test_valid_crystal_route_path?(")[").should be_false
      harness.test_valid_crystal_route_path?("Fortunes").should be_false
      harness.test_valid_crystal_route_path?("").should be_false
    end
  end

  describe "#collect_actions_into" do
    # A controller method whose body opens an `XML.build do … end` block and
    # contains a literal "end" string used to throw off do/end depth counting
    # and drop every method defined after it. Indentation tracking is immune.
    lines = [
      "module Invidious::Routes::API::Manifest",
      "  def self.get_dash_video_id(env)",
      "    body = String.build do |str|",
      "      str << \"end\"",
      "    end",
      "  end",
      "",
      "  def self.get_dash_video_playback(env)",
      "    Manifest.render(env)",
      "  end",
      "end",
    ]
    index = harness.test_collect_actions(lines, "manifest.cr")

    it "indexes every method regardless of body complexity" do
      index.has_key?("get_dash_video_id").should be_true
      index.has_key?("get_dash_video_playback").should be_true
    end

    it "resolves a relatively-named controller by namespace suffix" do
      callees = harness.test_resolve_action_callees(index, "Routes::API::Manifest", "get_dash_video_playback")
      callees.should_not be_nil
      if callees
        callees.map(&.[0]).should contain("Manifest.render")
      end
    end

    it "returns nil when no controller/action matches" do
      harness.test_resolve_action_callees(index, "Routes::Other", "missing").should be_nil
    end
  end

  describe "#crystal_dependency_path?" do
    it "skips the shards lib/ dependency directory" do
      harness.test_crystal_dependency_path?("/app/lib/kemal/src/kemal.cr").should be_true
      harness.test_crystal_dependency_path?("lib/foo/bar.cr").should be_true
    end

    it "keeps app dirs that merely contain the substring 'lib'" do
      # Regression: a real Amber app under `amber-library/` surfaced 0
      # routes because the old `path.includes?(\"lib\")` matched "library".
      harness.test_crystal_dependency_path?("/app/amber-library/config/routes.cr").should be_false
      harness.test_crystal_dependency_path?("/app/glib/src/app.cr").should be_false
      harness.test_crystal_dependency_path?("/app/src/routes.cr").should be_false
    end
  end
end
