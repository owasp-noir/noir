require "spec"
require "../../../src/miniparsers/python_route_extractor"

describe Noir::PythonRouteExtractor do
  describe "find_def_line" do
    it "finds the def immediately below a decorator" do
      lines = ["@app.route('/x')", "def handler():"]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "skips chained decorators, comments and blank lines" do
      lines = [
        "@app.route('/x')",
        "@login_required",
        "# a comment",
        "",
        "def handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(4)
    end

    it "walks past a multi-line decorator header" do
      lines = [
        "@app.route(",
        "    '/x',",
        "    methods=['GET']",
        ")",
        "def handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(4)
    end

    it "matches a class declaration too" do
      lines = ["@register", "class MyView:"]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "walks upward to the enclosing def when direction is :up" do
      lines = [
        "def existing():",
        "    pass",
        "@app.get('/x')",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 2, :up).should eq(0)
    end

    it "returns the original index when nothing matches" do
      lines = ["@app.route('/x')", "x = 1"]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(0)
    end

    it "ignores trailing comments with opening parenthesis" do
      lines = [
        "@route(\"/report\", method=\"GET\")  # note (",
        "def report():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "ignores trailing comments with closing parenthesis" do
      lines = [
        "@route(\"/report\", method=\"GET\")  # note )",
        "def report():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "does not treat '#' inside string literals as comments" do
      lines = [
        "@app.route(\"/tag/#anchor\")  # this is a comment (",
        "def tag_handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "handles multi-line decorators with continuation lines carrying comments" do
      lines = [
        "@app.route(",
        "    \"/endpoint/#part1\", # inline comment (",
        "    methods=[\"GET\"] # another comment )",
        ") # final comment (",
        "def handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(4)
    end

    it "skips intervening comment lines containing unbalanced parentheses" do
      lines = [
        "@app.route('/x')",
        "# TODO: add auth (legacy notes",
        "def handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(2)
    end
  end
end
