require "../models/output_builder"
require "../models/endpoint"
require "../models/access"
require "./markdown_cell"

@[Noir::OutputFormat(name: "access-matrix", description: "Markdown matrix of who can reach each endpoint", order: 65, structured: true)]
class OutputBuilderAccessMatrix < OutputBuilder
  include OutputBuilderMarkdownCell

  MARKS = {true => "Y", false => "-", nil => "?"}

  def print(endpoints : Array(Endpoint))
    # An outbound client declaration (Feign, `@HttpExchange`) is not served
    # here, so nobody reaches it.
    rows = endpoints.reject(&.internal).map { |endpoint| {endpoint, Access.of(endpoint)} }
    principals = Access.principals(rows.flat_map(&.[1]))

    columns = ["Endpoint"] + principals.map { |principal| markdown_code_span(sanitize_code_span_cell(principal.to_s)) } + ["Requires"]
    ob_puts "| #{columns.join(" | ")} |"
    ob_puts "| #{columns.map { "---" }.join(" | ")} |"

    rows.each do |endpoint, clauses|
      cells = [markdown_code_span(sanitize_code_span_cell("#{endpoint.method} #{endpoint.url}"))]
      principals.each { |principal| cells << MARKS[Access.cell(clauses, principal)] }
      cells << requires_cell(clauses)
      ob_puts "| #{cells.join(" | ")} |"
    end

    ob_puts ""
    ob_puts "Y allowed, - denied, ? unknown (a guard noir could not read)"
  end

  private def requires_cell(clauses : Array(Access::Clause)) : String
    return "no guard found" if clauses.empty?
    # Two unread clauses differ only in a fragment this cell does not show.
    text = clauses.map do |clause|
      atoms = clause.any_of.join(" | ")
      clause.any_of.size > 1 ? "(#{atoms})" : atoms
    end.uniq!.join(" & ")
    markdown_code_span(sanitize_code_span_cell(text))
  end
end
