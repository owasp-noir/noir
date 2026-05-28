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
end
