require "../../spec_helper"
require "../../../src/analyzer/engines/go_engine"

class GoEngineSpecHarness < Analyzer::Go::GoEngine
  def test_add_param_to_endpoint(param : Param, endpoint : Endpoint)
    add_param_to_endpoint(param, endpoint)
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

    # Callers hand it `Analyzer#base_relative_path`, which is rooted with a
    # leading `/` so the check never sees the absolute path.
    it "accepts the `/`-rooted scan-base-relative form" do
      Analyzer::Go::GoEngine.go_test_file?("/path/_examples/main.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("/_testdata/fixture.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("/path/to/server.go").should be_false
    end

    it "returns false for standard production files" do
      Analyzer::Go::GoEngine.go_test_file?("main.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("path/to/server.go").should be_false
    end

    # Helpers under these trees are test-only even when the file is not
    # `*_test.go` (toxiproxy `test/e2e/endpoint.go`).
    it "returns true for conventional test directories" do
      Analyzer::Go::GoEngine.go_test_file?("/test/e2e/endpoint.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("test/e2e/endpoint.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("/tests/fakes/a.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("/e2e/bench.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("/pkg/internal/test/helper.go").should be_true
    end

    it "matches those directory names as whole segments only" do
      Analyzer::Go::GoEngine.go_test_file?("/testing/harness/server.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/testutil/server.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/internal/integration/slack/webhook.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/mytest/x.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/e2e_keys/x.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/integrations/x.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/latest/x.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/api/e2e.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/pkg/tests.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("server.go").should be_false
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

describe "Analyzer::Go::GoEngine.drop_unslotted_path_params" do
  routed = ->(url : String, names : Array(String), line : Int32) do
    endpoint = Endpoint.new(url, "GET", names.map { |name| Param.new(name, "", "path") })
    endpoint.handler = Handler.new("h", "/app/h.go", line)
    endpoint
  end
  path_names = ->(endpoint : Endpoint) { endpoint.params.select(&.param_type.==("path")).map(&.name) }

  it "drops a slot the route lacks when the handler's sibling route adds it" do
    endpoints = Analyzer::Go::GoEngine.drop_unslotted_path_params([
      routed.call("/short", ["word"], 1),
      routed.call("/short/:word", ["word"], 1),
      routed.call("/v1/users/{user}/stats", ["user", "range"], 2),
      routed.call("/v1/users/{user}/stats/{range}", ["user", "range"], 2),
    ])
    endpoints.map { |endpoint| path_names.call(endpoint) }.should eq([[] of String, ["word"], ["user"], ["user", "range"]])
  end

  it "keeps a param whose slot may sit in a prefix noir could not resolve" do
    endpoints = Analyzer::Go::GoEngine.drop_unslotted_path_params([
      # `Group(fmt.Sprintf("/teams/:%s", "team"))`, `Group(s.base)`: one route each
      routed.call("/list", ["team"], 3),
      routed.call("/k", ["tenant"], 4),
      # the same handler on a resolved and an unresolved prefix
      routed.call("/p/:pid/info", ["pid"], 5),
      routed.call("/info", ["pid"], 5),
      # no handler location: nothing to compare
      Endpoint.new("/detail", "GET", [Param.new("project", "", "path")]),
    ])
    endpoints.map { |endpoint| path_names.call(endpoint) }.should eq([["team"], ["tenant"], ["pid"], ["pid"], ["project"]])
  end
end
