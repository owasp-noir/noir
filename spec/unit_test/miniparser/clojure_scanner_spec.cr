require "../../spec_helper"
require "../../../src/miniparsers/clojure_scanner"

# `skip_char_literal` returns the offset of the literal's last byte, so the
# whole token it consumed is `source[0..result]`.
private def read_char_literal(source : String) : String
  last = Noir::ClojureScanner.skip_char_literal(source, 0, source.bytesize)
  source.byte_slice(0, last + 1)
end

describe Noir::ClojureScanner do
  describe "skip_char_literal" do
    it "reads a single-character literal, reader-significant characters included" do
      read_char_literal("\\a rest").should eq("\\a")
      read_char_literal("\\\" rest").should eq("\\\"")
      read_char_literal("\\( rest").should eq("\\(")
      read_char_literal("\\) rest").should eq("\\)")
      read_char_literal("\\; rest").should eq("\\;")
    end

    it "ends a backslash literal at the backslash instead of escaping what follows" do
      # In a character literal `\\` *is* the backslash character; unlike a
      # string escape it does not swallow the character after it.
      read_char_literal("\\\\ rest").should eq("\\\\")
      read_char_literal("\\\\\"").should eq("\\\\")
    end

    it "reads the whole named literal, not just two characters" do
      # `\newline` must not leave `ewline` behind to be read as a symbol.
      read_char_literal("\\newline)").should eq("\\newline")
      read_char_literal("\\space]").should eq("\\space")
      read_char_literal("\\tab ").should eq("\\tab")
      read_char_literal("\\formfeed ").should eq("\\formfeed")
      read_char_literal("\\backspace ").should eq("\\backspace")
      read_char_literal("\\return ").should eq("\\return")
    end

    it "reads unicode and octal literals whole" do
      read_char_literal("\\u00e9 ").should eq("\\u00e9")
      read_char_literal("\\o101)").should eq("\\o101")
    end

    it "stops at the range limit without running past it" do
      Noir::ClojureScanner.skip_char_literal("\\", 0, 1).should eq(0)
      # `\newline` clipped to `\new` by the caller's limit.
      Noir::ClojureScanner.skip_char_literal("\\newline", 0, 4).should eq(3)
    end
  end

  describe "find_matching_delimiter" do
    it "does not count a `\\(` character literal as an open paren" do
      source = "(let [open \\(] open)"
      Noir::ClojureScanner.find_matching_delimiter(source, 0, '(', ')', source.bytesize)
        .should eq(source.bytesize - 1)
    end

    it "does not let a quote character literal open a string" do
      source = "(let [q \\\"] (str q \"x\"))"
      Noir::ClojureScanner.find_matching_delimiter(source, 0, '(', ')', source.bytesize)
        .should eq(source.bytesize - 1)
    end

    it "does not let a `\\;` character literal start a comment" do
      source = "(let [semi \\;] semi)"
      Noir::ClojureScanner.find_matching_delimiter(source, 0, '(', ')', source.bytesize)
        .should eq(source.bytesize - 1)
    end

    it "still treats a real `;` comment and a real string as opaque" do
      source = "(do ; )\n  \"( ; \")"
      Noir::ClojureScanner.find_matching_delimiter(source, 0, '(', ')', source.bytesize)
        .should eq(source.bytesize - 1)
    end
  end
end
