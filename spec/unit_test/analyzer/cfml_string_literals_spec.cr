require "../../spec_helper"
require "../../../src/analyzer/engines/cfml_engine"

# CFML string literals have exactly one escape: the delimiter doubled
# (`"say ""hi"""`, `'it''s'`). A backslash is an ORDINARY character, so
# `"C:\uploads\"` is a complete eleven-character string — the shape that
# used to break every scanner in this engine, because each of them treated
# `\` as escaping the quote that closes the literal and so left the run open
# for the rest of the file.
class CfmlEngineSpecHarness < Analyzer::Cfml::CfmlEngine
  def analyze
    @result
  end

  def split(raw : String) : Array(String)
    split_arguments(raw)
  end

  def arguments_of(raw : String) : Array(String)
    script_arguments(raw)
  end

  def paren_close(content : String, open_paren : Int32) : Int32?
    matching_paren(content, open_paren)
  end

  def strip_comments(content : String) : String
    strip_script_comments(content)
  end
end

describe Analyzer::Cfml::CfmlEngine do
  harness = CfmlEngineSpecHarness.new(create_test_options)

  describe "#split_arguments" do
    it "keeps a comma that sits inside a doubled-quote literal" do
      harness.split(%q(label = "report ""Q1"", final", page = 1))
        .should eq [%q(label = "report ""Q1"", final"), "page = 1"]
    end

    it "keeps a comma inside a doubled-quote literal in single quotes" do
      harness.split(%q(label = 'it''s, fine', page = 1))
        .should eq [%q(label = 'it''s, fine'), "page = 1"]
    end

    it "treats a doubled quote at the start and at the end of a literal as literal" do
      harness.split(%q(a = """quoted, value""", b = 2))
        .should eq [%q(a = """quoted, value"""), "b = 2"]
    end

    # The regression this file is named after. `\` is not an escape, so the
    # literal ends at the quote after it and the following comma is a real
    # separator. While `\` was read as an escape the run stayed open and
    # every later argument was swallowed by the first one.
    it "ends a literal at the quote following a backslash" do
      harness.split(%q(folder = "C:\uploads\", mask = "*.pdf"))
        .should eq [%q(folder = "C:\uploads\"), %q(mask = "*.pdf")]
    end

    it "leaves an interior backslash as an ordinary character" do
      harness.split(%q(pattern = "^\d{4}$", limit = 10))
        .should eq [%q(pattern = "^\d{4}$"), "limit = 10"]
    end

    # An odd run of quotes: `"a"""` is `a"`, and the run is closed by the
    # last quote, so the comma after it splits.
    it "closes the run on the unpaired quote of an odd run" do
      harness.split(%q(a = "x""", b = 2)).should eq [%q(a = "x"""), "b = 2"]
    end
  end

  describe "#script_arguments" do
    it "reports every argument of a signature holding a backslash default" do
      harness.arguments_of(%q(string folder = "C:\uploads\", string mask = "*.pdf"))
        .should eq ["folder", "mask"]
    end

    it "reports every argument of a signature holding a doubled-quote default" do
      harness.arguments_of(%q(string label = "report ""Q1"", final", numeric page = 1))
        .should eq ["label", "page"]
    end
  end

  describe "#matching_paren" do
    # `paren_content` feeds `script_arguments`, so a run that never closes
    # does not merely mis-split the arguments — it loses the whole call, and
    # with it the endpoint.
    it "finds the closing paren of a call whose literal ends in a backslash" do
      source = %q(remote function listUploads( string folder = "C:\uploads\", string mask = "*.pdf" ) {})
      close = harness.paren_close(source, source.index!('('))
      close.should eq source.index(") {")
    end

    it "ignores a paren inside a doubled-quote literal" do
      # `%q` is unusable here: the `)` inside the literal is unbalanced.
      source = "route( \"/a\"\") b\", \"main.index\" ) "
      close = harness.paren_close(source, source.index!('('))
      close.should eq source.rindex(')')
    end
  end

  describe "#strip_script_comments" do
    it "does not mistake the tail of a backslash-terminated literal for a comment" do
      source = %Q(var root = "C:\\uploads\\";\n// gone\nroute( "/files" );\n)
      stripped = harness.strip_comments(source)
      stripped.should contain(%q(route( "/files" )))
      stripped.should_not contain("gone")
    end
  end
end
