# Escaping for text that goes into a GitHub-flavored Markdown table cell.
# Shared by `-f markdown-table` and the markdown diff report, which both put
# repo-derived strings (routes, param names) into table rows.
module OutputBuilderMarkdownCell
  # A code span's opening delimiter must be longer than the longest backtick
  # run inside it (CommonMark), or a backtick in a param name closes the span
  # early: ``md`tick (query)`` rendered as the code "md", then loose text, then
  # a stray backtick that ran on into the rest of the row. Content that starts
  # or ends with a backtick is padded with a space, which CommonMark strips
  # exactly one of, so the backtick survives as content.
  private def markdown_code_span(content : String) : String
    longest = content.scan(/`+/).max_of?(&.[0].size) || 0
    return "`#{content}`" if longest.zero?

    fence = "`" * (longest + 1)
    pad = content.starts_with?('`') || content.ends_with?('`') ? " " : ""
    "#{fence}#{pad}#{content}#{pad}#{fence}"
  end

  # Cells rendered as inline text rather than inside a code span. A backtick
  # here would open a span of its own and swallow part of a URL, so it is
  # backslash-escaped — which only works outside a code span, hence the split
  # from `sanitize_markdown_cell`.
  private def sanitize_text_cell(content : String) : String
    sanitize_markdown_cell(content).gsub('`', "\\`")
  end

  # Sanitizer for content rendered inside code spans. CommonMark does not
  # recognize HTML entity references or backslash escapes inside code spans
  # (§6.1/§6.3), so `<`, `>`, and `\` must remain literal. Only table column
  # delimiters (`|`) and line breaks (`\r`, `\n`) are escaped/normalized.
  private def sanitize_code_span_cell(content : String) : String
    content.to_s
      .gsub('|', "\\|") # Escape pipes
      .gsub("\r", "")   # Remove carriage returns
      .gsub("\n", " ")  # Replace newlines with space
  end

  private def sanitize_markdown_cell(content : String) : String
    content.to_s
      .gsub('\\', "\\\\") # Escape backslashes first
      .gsub('|', "\\|")   # Escape pipes
      .gsub('<', "&lt;")  # Escape HTML start tag
      .gsub('>', "&gt;")  # Escape HTML end tag
      .gsub("\r", "")     # Remove carriage returns
      .gsub("\n", " ")    # Replace newlines with space
  end
end
