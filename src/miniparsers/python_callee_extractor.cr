require "../ext/tree_sitter/tree_sitter"

# Walks a Python source snippet (typically a function body) and returns
# the 1-hop callees inside it. Used by analyzers that want to expose
# `Endpoint.callees` for AI code reviewers.
#
# Intentionally simple: identifier and attribute callees only. Calls
# made through `getattr`, `__import__`, `globals()[...]`, etc. are out
# of scope — `callees` is a useful prior, not a complete graph.
module Noir::PythonCalleeExtractor
  # Builtins and small stdlib helpers carry no security signal; filtering
  # them keeps the list short enough to fit in an AI context window.
  # Anything framework-specific (Flask `request.*`, `jsonify`, `abort`,
  # `redirect`, …) is intentionally kept — those tell a reviewer how the
  # endpoint shapes input and output.
  BUILTINS = Set{
    "print", "len", "range", "int", "str", "list", "dict", "tuple", "set",
    "bool", "float", "type", "isinstance", "issubclass", "id", "hash",
    "enumerate", "zip", "map", "filter", "sorted", "reversed",
    "min", "max", "sum", "abs", "round", "pow", "divmod",
    "iter", "next", "open", "input",
    "getattr", "setattr", "hasattr", "delattr",
    "any", "all", "vars", "dir", "locals", "globals", "callable",
    "format", "repr", "ascii", "ord", "chr", "hex", "oct", "bin",
    "super",
  }

  # Parse `source` as Python and return every callee inside the first
  # function body found. Each entry is {name, 0-based row within source}.
  # The caller is responsible for converting rows to absolute file lines.
  def self.calls_in(source : String) : Array(Tuple(String, Int32))
    result = [] of Tuple(String, Int32)
    Noir::TreeSitter.parse_python(source) do |root|
      walk(root, source, result)
    end
    result
  end

  private def self.walk(node : LibTreeSitter::TSNode, source : String, result : Array(Tuple(String, Int32)))
    if Noir::TreeSitter.node_type(node) == "call"
      if func = Noir::TreeSitter.field(node, "function")
        name = callee_text(func, source)
        if !name.empty? && !BUILTINS.includes?(name) && !name.starts_with?("__")
          row = Noir::TreeSitter.node_start_row(func)
          result << {name, row}
        end
      end
    end
    Noir::TreeSitter.each_named_child(node) do |child|
      walk(child, source, result)
    end
  end

  private def self.callee_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier", "attribute"
      Noir::TreeSitter.node_text(node, source)
    else
      ""
    end
  end
end
