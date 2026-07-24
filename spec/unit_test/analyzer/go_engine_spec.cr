require "../../spec_helper"
require "../../../src/analyzer/engines/go_engine"

class GoEngineSpecHarness < Analyzer::Go::GoEngine
  def test_add_param_to_endpoint(param : Param, endpoint : Endpoint)
    add_param_to_endpoint(param, endpoint)
  end

  def test_add_static_path_if_valid(static_path : Hash(String, String), public_dirs : Array(Hash(String, String)))
    add_static_path_if_valid(static_path, public_dirs)
  end
end

describe Analyzer::Go::GoEngine do
  harness = GoEngineSpecHarness.new(create_test_options)

  describe ".go_test_file?" do
    it "returns true for test files ending with _test.go" do
      Analyzer::Go::GoEngine.go_test_file?("main_test.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("path/to/server_test.go").should be_true
    end

    it "returns true for path components starting with _" do
      Analyzer::Go::GoEngine.go_test_file?("path/_examples/main.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("_testdata/fixture.go").should be_true
    end

    it "returns false for standard production files" do
      Analyzer::Go::GoEngine.go_test_file?("main.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("path/to/server.go").should be_false
    end
  end

  describe "#add_param_to_endpoint" do
    it "adds parameter to endpoint when all properties are valid" do
      endpoint = Endpoint.new("/api/users", "GET")
      param = Param.new("id", "", "query")

      harness.test_add_param_to_endpoint(param, endpoint)

      endpoint.params.size.should eq(1)
      endpoint.params[0].name.should eq("id")
    end

    it "ignores empty parameters" do
      endpoint = Endpoint.new("/api/users", "GET")
      param = Param.new("", "", "query")

      harness.test_add_param_to_endpoint(param, endpoint)

      endpoint.params.size.should eq(0)
    end
  end

  describe "#add_static_path_if_valid" do
    it "adds static path mapping if both static_path and file_path are present" do
      public_dirs = [] of Hash(String, String)
      mapping = {
        "static_path" => "/assets",
        "file_path"   => "public/assets",
      }

      harness.test_add_static_path_if_valid(mapping, public_dirs)

      public_dirs.size.should eq(1)
      public_dirs[0]["static_path"].should eq("/assets")
    end

    it "does not add static path mapping if static_path is empty" do
      public_dirs = [] of Hash(String, String)
      mapping = {
        "static_path" => "",
        "file_path"   => "public/assets",
      }

      harness.test_add_static_path_if_valid(mapping, public_dirs)

      public_dirs.size.should eq(0)
    end
  end

  describe ".strip_comments" do
    it "blanks line comments while keeping the line count stable" do
      source = <<-GO
        a := 1
        // rootCmd.Flags().StringVar(&dead, "ghost", "", "")
        b := 2
        GO

      stripped = Analyzer::Go::GoEngine.strip_comments(source)

      stripped.lines.size.should eq(source.lines.size)
      stripped.should_not contain("ghost")
      stripped.lines[0].should eq("a := 1")
      stripped.lines[2].should eq("b := 2")
    end

    it "blanks block comments while keeping the line count stable" do
      source = <<-GO
        a := 1
        /*
        StringVar(&dead, "ghost", "", "")
        */
        b := 2
        GO

      stripped = Analyzer::Go::GoEngine.strip_comments(source)

      stripped.lines.size.should eq(source.lines.size)
      stripped.should_not contain("ghost")
      stripped.lines[4].should eq("b := 2")
    end

    it "keeps a trailing comment's code but drops the comment" do
      stripped = Analyzer::Go::GoEngine.strip_comments(%(x := "keep" // "ghost"))

      stripped.should contain("keep")
      stripped.should_not contain("ghost")
    end

    # Go raw strings take no escapes and may span newlines, so a `//` or
    # `/*` inside one is ordinary text — a C-family stripper that only
    # knows `"` and `'` would truncate the literal here.
    it "leaves // and /* inside a raw string literal alone" do
      stripped = Analyzer::Go::GoEngine.strip_comments("x := `keep // this /* and this */`")

      stripped.should eq("x := `keep // this /* and this */`")
    end

    it "leaves // inside an interpreted string alone" do
      stripped = Analyzer::Go::GoEngine.strip_comments(%(url := "https://x.example/a//b"))

      stripped.should eq(%(url := "https://x.example/a//b"))
    end

    it "does not end a string literal on an escaped quote" do
      stripped = Analyzer::Go::GoEngine.strip_comments(%(x := "a \\" b // still string"))

      stripped.should eq(%(x := "a \\" b // still string"))
    end

    it "returns the source untouched when it holds no comment markers" do
      source = %(x := "plain")

      Analyzer::Go::GoEngine.strip_comments(source).should eq(source)
    end
  end
end
