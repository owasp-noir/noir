require "../models/endpoint"
require "./callee_extractor_base"
require "./swift_callee_extractor"

# Best-effort 1-hop callee extraction for Objective-C method bodies. Mirrors
# `SwiftCalleeExtractor` but understands the message-send syntax
# (`[receiver selector:arg]`) that dominates Objective-C — the selector is the
# callee. C-style function calls (`CGRectMake(...)`) are picked up too.
#
# Comment / string stripping is shared with the Swift extractor (Objective-C
# uses the same `//`, `/* */`, and `"..."` lexical forms).
module Noir::ObjcCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  # Keywords and primitive type names that can sit where a selector / call
  # name would, but are never a 1-hop callee.
  RESERVED = Set{
    "if", "else", "for", "while", "do", "switch", "case", "default",
    "return", "break", "continue", "goto", "sizeof", "self", "super",
    "nil", "Nil", "NULL", "YES", "NO", "id", "void", "BOOL", "in",
    "typeof", "__typeof", "__bridge", "__weak", "__strong", "instancetype",
    "const", "static", "extern", "inline", "_cmd", "block", "weakSelf",
  }

  # Pure memory-management selectors — real calls, but noise as callees.
  MEMORY_SELECTORS = Set{
    "alloc", "init", "new", "retain", "release", "autorelease",
    "dealloc", "copy", "mutableCopy",
  }

  # `[receiver selector...]` where the receiver is an identifier / dotted
  # property chain / `self` — captures the first selector keyword.
  MSG_IDENT_RECEIVER_RE = /\[\s*(?:[A-Za-z_]\w*)(?:\s*\.\s*[A-Za-z_]\w*)*\s+([A-Za-z_]\w*)\s*[:\]]/
  # The selector of an outer message whose receiver is itself a bracketed
  # subexpression: `[[Foo bar] selector:...]` -> the `] selector` boundary.
  MSG_BRACKET_RECEIVER_RE = /\]\s+([A-Za-z_]\w*)\s*[:\]]/
  # A C-style function call (`CGRectMake(...)`), not a `.method(`/`](` form.
  C_CALL_RE = /(?<![.\w\]])([A-Za-z_]\w*)\s*\(/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    block_comment_depth = 0
    in_string = false

    body.lines.each_with_index do |line, index|
      stripped, block_comment_depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
        line, block_comment_depth, in_string
      )
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    {MSG_IDENT_RECEIVER_RE, MSG_BRACKET_RECEIVER_RE}.each do |re|
      line.scan(re) { |m| add_entry(entries, m[1], file_path, line_number) }
    end
    line.scan(C_CALL_RE) { |m| add_entry(entries, m[1], file_path, line_number) }
  end

  private def add_entry(entries : Array(Entry), name : String, file_path : String, line_number : Int32)
    return if name.empty? || RESERVED.includes?(name) || MEMORY_SELECTORS.includes?(name)
    entries << {name, file_path, line_number}
  end
end
