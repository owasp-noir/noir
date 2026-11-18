require "../models/output_builder"
require "../models/endpoint"
require "./markdown_cell"

@[Noir::OutputFormat(name: "markdown-table", description: "Markdown table", order: 60, structured: true)]
class OutputBuilderMarkdownTable < OutputBuilder
  include OutputBuilderMarkdownCell

  def print(endpoints : Array(Endpoint))
    show_project = endpoints.any? { |endpoint| !report_projects(endpoint).empty? }
    show_path = any_to_bool(@options["include_path"]?)
    columns = ["Endpoint", "Protocol", "Params"]
    columns << "Project" if show_project
    columns << "Source" if show_path
    ob_puts "| #{columns.join(" | ")} |"
    ob_puts "| #{columns.map { |column| "-" * column.size }.join(" | ")} |"

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
                          content = "#{sanitize_code_span_cell(param.name)} (#{sanitize_code_span_cell(param.param_type)})"
                          cell << markdown_code_span(content) << ' '
                        end
                      end
                    end

      # A code span, like the diff report's endpoint column: nothing in a
      # route (`[x](…)`, `*`, `_`) can render as Markdown inside one, and the
      # route reads exactly as written.
      endpoint_cell = markdown_code_span(sanitize_code_span_cell("#{endpoint.method} #{endpoint.url}"))
      cells = [endpoint_cell, sanitize_text_cell(endpoint.protocol), params_text]
      cells << sanitize_text_cell(report_projects(endpoint)) if show_project
      if show_path
        paths = endpoint.details.code_paths.map do |location|
          line = location.line
          path = line ? "#{location.path}:#{line}" : location.path
          markdown_code_span(sanitize_code_span_cell(path))
        end
        cells << paths.join("<br>")
      end
      ob_puts "| #{cells.join(" | ")} |"
    end
  end
end
