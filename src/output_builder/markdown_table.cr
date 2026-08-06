require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderMarkdownTable < OutputBuilder
  def print(endpoints : Array(Endpoint))
    ob_puts "| Endpoint | Protocol | Params |"
    ob_puts "| -------- | -------- | ------ |"

    endpoints.each do |endpoint|
      # `params` is a non-nilable Array, so the `-` placeholder used to sit
      # behind an `unless params.nil?` that could never be false: a param-less
      # endpoint rendered an empty cell instead. Branch on `empty?`, which is
      # the condition that was meant.
      params_text = if endpoint.params.empty?
                      "-"
                    else
                      String.build do |cell|
                        endpoint.params.each do |param|
                          content = "#{sanitize_markdown_cell(param.name)} (#{sanitize_markdown_cell(param.param_type)})"
                          cell << markdown_code_span(content) << ' '
                        end
                      end
                    end

      ob_puts "| #{sanitize_text_cell(endpoint.method)} #{sanitize_text_cell(endpoint.url)} | #{sanitize_text_cell(endpoint.protocol)} | #{params_text} |"
    end
  end

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
