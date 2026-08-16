require "../../spec_helper"
require "../../../src/analyzer/analyzers/python/tornado"

class TornadoDocstringHarness < Analyzer::Python::Tornado
  def docstring_flags(lines : Array(String)) : Array(Bool)
    compute_docstring_line_flags(lines)
  end
end

# The flags decide which lines sit inside a module docstring and are therefore
# not code. Getting one wrong does not drop a line — it flips every line after
# it, because the triple-quote state is carried forward across the whole file.
describe "Tornado docstring line flags" do
  harness = TornadoDocstringHarness.new(create_test_options)

  it "closes a single-line string that ends in an escaped backslash" do
    # A Windows path, then a docstring opened later on the SAME line. The
    # one-character lookback this replaces read the closing quote of `"C:\\"`
    # as escaped, so the scan ran off the end of the line and never saw the
    # `"""` — leaving the docstring unopened, and the closing `"""` on the next
    # line free to open one instead. Every following line then counted as
    # docstring, and its routes disappeared.
    lines = <<-PY.split("\n")
      PATH = "C:\\\\"; DOC = """start
      of a docstring"""
      app.add_handlers(".*", [(r"/late", LateHandler)])
      PY

    harness.docstring_flags(lines).should eq([false, true, false])
  end

  it "still treats an escaped quote as part of the string" do
    # Odd number of backslashes: the quote really is escaped, the string runs
    # on, and the `"""` inside it is not a docstring opener.
    lines = <<-PY.split("\n")
      MSG = "he said \\"\\"\\" and left"
      app.add_handlers(".*", [(r"/after", AfterHandler)])
      PY

    harness.docstring_flags(lines).should eq([false, false])
  end

  it "tracks a plain module docstring across lines" do
    lines = <<-PY.split("\n")
      """Module docs.
      Second line.
      """
      app.add_handlers(".*", [(r"/x", XHandler)])
      PY

    harness.docstring_flags(lines).should eq([false, true, true, false])
  end
end
