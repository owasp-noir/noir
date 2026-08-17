require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/engines/python_engine"

# `return_literal_value` and `parse_function_def` are instance methods on the
# abstract engine, so a minimal concrete subclass exposes them.
class PythonEngineLiteralHarness < Analyzer::Python::PythonEngine
  def literal(data : String) : String
    return_literal_value(data)
  end

  def parse_def(source : String)
    parse_function_def(source.lines, 0)
  end
end

private def literal_harness
  PythonEngineLiteralHarness.new(create_test_options)
end

describe Analyzer::Python::PythonEngine do
  describe "#return_literal_value" do
    it "unwraps quoted strings and keeps numbers" do
      h = literal_harness
      h.literal(%q("abc")).should eq "abc"
      h.literal("'abc'").should eq "abc"
      h.literal(%q("""abc""")).should eq "abc"
      h.literal("7").should eq "7"
      h.literal("1.5").should eq "1.5"
    end

    it "spells Python booleans for the wire and treats None/... as absent" do
      h = literal_harness
      h.literal("True").should eq "true"
      h.literal("False").should eq "false"
      h.literal("None").should eq ""
      h.literal("...").should eq ""
      h.literal("Ellipsis").should eq ""
    end

    # The regression this exists for. `Param#value` is what the curl /
    # httpie / PowerShell builders put on the wire and what the OAS builders
    # publish as an `enum`, so `q: str = Query()` must not produce `?q=Query()`
    # and `x_token: str = Header(None)` must not produce
    # `-H 'x_token: Header(None)'`.
    it "gives a bare FastAPI marker no value" do
      h = literal_harness
      h.literal("Query()").should eq ""
      h.literal("Header(None)").should eq ""
      h.literal("Cookie(None)").should eq ""
      h.literal("Form(...)").should eq ""
      h.literal("File(...)").should eq ""
      h.literal("Header(default=None, include_in_schema=False)").should eq ""
    end

    it "recovers the default a marker actually carries" do
      h = literal_harness
      h.literal(%q(Query("abc"))).should eq "abc"
      h.literal("Query(False)").should eq "false"
      h.literal("Query(7)").should eq "7"
      h.literal(%q(Header(default="hv"))).should eq "hv"
      h.literal(%q(fastapi.Query("ns"))).should eq "ns"
      # `default=` wins over position no matter where it appears.
      h.literal(%q(Query(description="a: b, c", default="real"))).should eq "real"
      # `=` inside a quoted positional is not a keyword argument.
      h.literal(%q(Query("a=b"))).should eq "a=b"
    end

    it "gives any other expression no value" do
      h = literal_harness
      h.literal("get_db()").should eq ""
      h.literal("SOME_CONSTANT").should eq ""
      h.literal("[1, 2]").should eq ""
    end
  end

  describe "#parse_function_def" do
    # `{` / `}` used to contribute no depth, so a comma inside a dict or set
    # default split the parameter list and produced a parameter literally
    # named `"y"}`.
    it "does not split a parameter list on a comma inside braces" do
      params = literal_harness.parse_def(%q(def s(tags: set = {"x", "y"}, after: str = "tail"):)).not_nil!.params
      params.map(&.name).should eq ["tags", "after"]
      params[1].default.should eq %q("tail")
    end

    it "keeps colons that are not the annotation separator" do
      params = literal_harness.parse_def(%q(def d(cfg: dict = {"a": 1}, z: str = "last"):)).not_nil!.params
      params.map(&.name).should eq ["cfg", "z"]
      params[0].default.should eq %q({"a": 1})
    end

    # Nothing in this scanner was quote-aware, so any delimiter inside a
    # string default was counted as structure. `"("` / `"["` left the depth
    # permanently open and every parameter of the function was lost with
    # nothing logged; `"x,y"` split mid-literal into a parameter named `y"`.
    #
    # Spelled with escaped double quotes rather than `%q(...)`: the `"("`
    # case leaves the `%q` parens unbalanced and fails to parse.
    it "treats delimiters inside a string default as text" do
      h = literal_harness
      {
        "(",
        "[",
        "{",
        "}",
        "x,y",
        "a:b",
      }.each do |sep|
        header = "def f(sep: str = \"#{sep}\", after: str = \"tail\"):"
        params = h.parse_def(header).not_nil!.params
        params.map(&.name).should eq ["sep", "after"]
        h.literal(params[0].default).should eq sep
        h.literal(params[1].default).should eq "tail"
      end
    end

    it "does not end a quoted run on an escaped quote" do
      header = "def f(sep: str = \"a\\\"b,c\", after: str = \"tail\"):"
      params = literal_harness.parse_def(header).not_nil!.params
      params.map(&.name).should eq ["sep", "after"]
      h = literal_harness
      h.literal(params[1].default).should eq "tail"
    end

    it "still splits name from type on the annotation colon" do
      params = literal_harness.parse_def("def f(item_id: int, q: str = None):").not_nil!.params
      params.map(&.name).should eq ["item_id", "q"]
      params.map(&.type).should eq ["int", "str"]
      params[1].default.should eq "None"
    end
  end
end
