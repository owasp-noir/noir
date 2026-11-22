require "../ext/tree_sitter/tree_sitter"

module Noir::PythonMethodGuard
  extend self

  # Scope parameter extraction to the suites a request can enter. Only
  # specialize an entry if/elif chain of literal method comparisons, before
  # arbitrary handler code can rebind the request or change its method.
  # Nested conditionals, exception handlers and other control flow keep
  # their ordinary scan. The original handler is still used for locations.
  def lines_for(lines : Array(String), method : String, *, request_argument : Bool = false) : Array(String)
    return lines unless lines.any?(&.includes?("request.method"))
    source = lines.join('\n')
    scoped = lines.dup
    TreeSitter.parse_python(source) do |root|
      return lines if TreeSitter.node_has_error?(root)
      handler = TreeSitter.first_named_child(root)
      return lines unless handler && TreeSitter.node_type(handler) == "function_definition"
      parameters = TreeSitter.field(handler, "parameters") || return lines
      signature = TreeSitter.node_text(parameters, source)
      if request_argument
        # DRF passes the request immediately after the action's receiver.
        return lines unless signature.matches?(/\A\(\s*\w+\s*,\s*request\s*[:,)]/)
      else
        # Flask and Quart expose a proxy. A handler argument can shadow it.
        return lines if signature.matches?(/\brequest\b/)
      end
      body = TreeSitter.field(handler, "body") || return lines
      TreeSitter.each_named_arg(body) do |statement|
        if TreeSitter.node_type(statement) == "expression_statement"
          value = TreeSitter.first_named_child(statement)
          next if value && TreeSitter.node_type(value) == "string" && TreeSitter.node_text(value, source).matches?(/\A[ru]?['"]/i)
        end
        break unless TreeSitter.node_type(statement) == "if_statement"
        if scope_guard(statement, source, method, scoped)
          # A direct return in the selected suite exits the handler.
          scoped = scoped.first(TreeSitter.node_end_row(statement) + 1)
        end
        break
      end
    end
    scoped
  rescue
    lines
  end

  private def scope_guard(statement, source : String, method : String, lines : Array(String)) : Bool
    clauses = [statement]
    TreeSitter.each_named_child(statement) do |child|
      clauses << child if TreeSitter.node_type(child).in?("elif_clause", "else_clause")
    end

    selected = nil
    clauses.each do |clause|
      block = TreeSitter.field(clause, "consequence") || TreeSitter.field(clause, "body") || return false
      # Keep inline suites intact. A single line may also carry a read.
      start = LibTreeSitter.ts_node_start_point(block)
      return false unless lines[start.row].byte_slice(0, start.column).blank?
      if condition = TreeSitter.field(clause, "condition")
        guard = TreeSitter.node_text(condition, source).match(/\Arequest\.method\s*==\s*(["'])([A-Z]+)\1\z/) || return false
        next unless guard[2] == method
      end
      selected ||= block
    end

    first = TreeSitter.node_start_row(statement)
    last = TreeSitter.node_end_row(statement)
    indent = lines[first][/^\s*/]
    if block = selected
      # Keep the suite at its original indentation so downstream parsers
      # can still resolve calls and aliases in valid Python.
      lines.fill("", first, TreeSitter.node_start_row(block) - first)
      lines[first] = "#{indent}if True:"
      tail = TreeSitter.node_end_row(block) + 1
      lines.fill("", tail, last - tail + 1)
      TreeSitter.each_named_child(block) do |child|
        return true if TreeSitter.node_type(child) == "return_statement"
      end
    else
      lines.fill("", first, last - first + 1)
      lines[first] = "#{indent}pass"
    end
    false
  end
end
