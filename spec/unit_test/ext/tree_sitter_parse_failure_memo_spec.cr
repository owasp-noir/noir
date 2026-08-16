require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

# `parse_timeout_micros` bounds one `ts_parser_parse_string` call, but the
# same file is handed to every analyzer of its language — nine Rust analyzers
# each parsed the same unparsable `.rs` file and each burned the full ceiling,
# so a 10 s bound cost 90 s. The verdict is a pure function of (content,
# grammar), so it is remembered.
describe "Noir::TreeSitter parse-failure memo" do
  # Big enough that even the first parse cannot finish inside a 1 µs ceiling,
  # small enough that the suite does not notice it.
  pathological = "x = " + ("(" * 20_000) + "1\n"

  it "raises on the first parse and skips the parse entirely on the next" do
    previous = Noir::TreeSitter.parse_timeout_micros
    Noir::TreeSitter.parse_timeout_micros = 1_u64
    begin
      before = Noir::TreeSitter.parse_failure_count

      expect_raises(Exception, /timed out/) do
        Noir::TreeSitter.parse_python(pathological) { |root| root }
      end
      Noir::TreeSitter.parse_failure_count.should eq(before + 1)

      # Second call never reaches tree-sitter: a different message, and no
      # second entry for the same (content, grammar) pair.
      expect_raises(Exception, /already failed to parse/) do
        Noir::TreeSitter.parse_python(pathological) { |root| root }
      end
      Noir::TreeSitter.parse_failure_count.should eq(before + 1)
    ensure
      Noir::TreeSitter.parse_timeout_micros = previous
    end
  end

  it "keys the memo on the grammar, so another language still tries" do
    previous = Noir::TreeSitter.parse_timeout_micros
    Noir::TreeSitter.parse_timeout_micros = 1_u64
    begin
      source = pathological + "# grammar-keyed\n"
      before = Noir::TreeSitter.parse_failure_count

      expect_raises(Exception, /timed out/) do
        Noir::TreeSitter.parse_python(source) { |root| root }
      end
      # Same bytes, different grammar: not a hit, so it parses (and times
      # out) on its own account.
      expect_raises(Exception, /timed out/) do
        Noir::TreeSitter.parse_go(source) { |root| root }
      end

      Noir::TreeSitter.parse_failure_count.should eq(before + 2)
    ensure
      Noir::TreeSitter.parse_timeout_micros = previous
    end
  end

  it "does not remember a source that parses" do
    before = Noir::TreeSitter.parse_failure_count

    Noir::TreeSitter.parse_python("def f():\n    pass\n") { |root| root }

    Noir::TreeSitter.parse_failure_count.should eq(before)
  end

  it "forgets everything when the scan-scoped memos are cleared" do
    previous = Noir::TreeSitter.parse_timeout_micros
    Noir::TreeSitter.parse_timeout_micros = 1_u64
    begin
      expect_raises(Exception) do
        Noir::TreeSitter.parse_python(pathological + "# cleared\n") { |root| root }
      end
      Noir::TreeSitter.parse_failure_count.should be > 0

      Noir::ExtractionResultCache.clear_all

      Noir::TreeSitter.parse_failure_count.should eq(0)
    ensure
      Noir::TreeSitter.parse_timeout_micros = previous
    end
  end
end
