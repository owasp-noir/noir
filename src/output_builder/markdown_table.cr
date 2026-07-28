require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderMarkdownTable < OutputBuilder
  def print(endpoints : Array(Endpoint))
    ob_puts "| Endpoint | Protocol | Params |"
    ob_puts "| -------- | -------- | ------ |"

    endpoints.each do |endpoint|
      if !endpoint.params.nil?
        params_text = String.build do |cell|
          endpoint.params.each do |param|
            cell << '`' << sanitize_markdown_cell(param.name)
            cell << " (" << sanitize_markdown_cell(param.param_type) << ")` "
          end
        end
        ob_puts "| #{sanitize_markdown_cell(endpoint.method)} #{sanitize_markdown_cell(endpoint.url)} | #{sanitize_markdown_cell(endpoint.protocol)} | #{params_text} |"
      else
        ob_puts "| #{sanitize_markdown_cell(endpoint.method)} #{sanitize_markdown_cell(endpoint.url)} | #{sanitize_markdown_cell(endpoint.protocol)} | - |"
      end
    end
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
