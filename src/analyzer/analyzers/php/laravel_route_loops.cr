require "../../engines/php_engine"
require "../../../minilexers/php_lexer"

# Laravel routes registered in a `foreach` over a constant literal array:
#
#   $endpoints = ['ping' => PingController::class, ...];
#   foreach ($endpoints as $endpoint => $controller) {
#       Route::match(['get', 'post'], "{$endpoint}{format?}", $controller);
#   }
#
# The body is scanned once per entry, the loop variables replaced by that
# entry, so each route gets its literal path and its handler. Anything the
# source does not prove constant keeps the as-written scan.
module Analyzer::Php
  class Laravel < PhpEngine
    # One entry of a literal PHP array: its string key (nil in a list) and
    # the value's source, which is a string literal, `X::class` or
    # `[X::class, 'method']`.
    record LoopEntry, key : String?, value : String

    # A literal array assigned at `pos` (-1: before the body being scanned).
    record LiteralArray, pos : Int32, entries : Array(LoopEntry)

    # Body scans one route file may spend on loop expansion, nested loops
    # included: an entry of an inner loop costs one per outer entry.
    # ponytail: a fixed budget per file; past it, loops keep the as-written scan.
    class LoopBudget
      MAX = 512

      @left = MAX

      # Set by the scan of a per-entry body that still interpolates a
      # variable into a route argument (see `flag_unresolved_route_args`).
      property? unresolved = false

      def take(count : Int32) : Bool
        return false if count > @left
        @left -= count
        true
      end
    end

    private record RouteLoop, start : Int32, body : String, body_start : Int32, body_end : Int32,
      key_var : String?, value_var : String, entries : Array(LoopEntry)

    ASSIGNED_ARRAY_RE = /(?<![\w$>:])\$(\w+)\s*=\s*(\[|array\s*\()/
    # Every write to a variable: assignment (also through a subscript or a
    # compound operator), a foreach / destructuring target, a reference, a
    # mutating builtin or `unset`.
    ASSIGNMENT_RE     = /(?<![\w$>:])\$(\w+)\s*(?:\[[^\]]*\]\s*)*(?:[.+\-*\/%|&^]|\?\?|<<|>>)?=(?![=>])/
    FOREACH_BIND_RE   = /\bas\s+&?\s*\$(\w+)(?:\s*=>\s*&?\s*\$(\w+))?/
    REFERENCE_RE      = /&\s*\$(\w+)/
    MUTATING_CALL_RE  = /\b(?:array_(?:push|unshift|splice|pop|shift|walk)|[uk]?sort|r?sort|u?[ak]r?sort|shuffle|unset|settype|global)\b\s*\(?\s*\$(\w+)/
    DESTRUCTURE_RE    = /(?:\blist\s*\(|\[)([^\[\]();=]*)[\])]\s*=(?![=>])/
    PARAM_LIST_RE     = /\b(?:function|fn)\s*&?\s*\w*\s*\(([^)]*)\)/
    DYNAMIC_VARS_RE   = /\$\$|\$\{|\b(?:extract|parse_str|compact)\s*\(|\$GLOBALS\b/
    LOOP_CONTROL_RE   = /\b(?:continue|break|goto)\b/
    SCOPE_RE          = /\b(?:function|class|trait|interface|enum)\b/
    FOREACH_RE        = /\bforeach\s*\(/
    FOREACH_HEAD_RE   = /\A\s*(\$\w+|\[.*\]|array\s*\(.*\))\s+as\s+(?:\$(\w+)\s*=>\s*)?\$(\w+)\s*\z/m
    ARRAY_ENTRY_RE    = /\A(?:(['"])([^'"$\\]*)\1\s*=>\s*)?(.+)\z/m
    ARRAY_VALUE_RE    = /\A(?:'[^'\\]*'|"[^"$\\]*"|\\?[A-Za-z_][\w\\]*::class|\[\s*\\?[A-Za-z_][\w\\]*::class\s*,\s*['"]\w+['"]\s*\])\z/
    ARRAY_SPLIT_RULES = Noir::TopLevelSplit::Rules.new
    LOOP_VAR_USE_RE   = /\{\$(\w+)\}|\$(\w+)\b/
    STRING_LITERAL_RE = /\A(['"])(.*)\1\z/m
    # A route call (or a call chained on one) whose string argument still
    # interpolates a variable after substitution: an inner loop that was not
    # expanded, or a value the body computes.
    UNRESOLVED_ROUTE_ARG_RE = /(?:\bRoute::|->)\s*\w+\s*\(\s*(?:[^;()"]*?,\s*)?"[^"]*\$[^"]*"/

    # Names `code` writes to, with how many times (a reference or a mutating
    # call counts twice: never constant).
    private def variable_writes(code : String) : Hash(String, Int32)
      writes = Hash(String, Int32).new(0)
      code.scan(ASSIGNMENT_RE) { |m| writes[m[1]] += 1 }
      code.scan(FOREACH_BIND_RE) do |m|
        writes[m[1]] += 1
        m[2]?.try { |name| writes[name] += 1 }
      end
      code.scan(DESTRUCTURE_RE) { |m| m[1].scan(/\$(\w+)/) { |v| writes[v[1]] += 2 } }
      code.scan(REFERENCE_RE) { |m| writes[m[1]] += 2 }
      code.scan(MUTATING_CALL_RE) { |m| writes[m[1]] += 2 }
      writes
    end

    # `$name = [...]` literal arrays the file assigns once, at file scope, and
    # never writes to again anywhere (a reassignment, `$name[] = …`,
    # `array_push($name, …)`, a reference): only then does a loop over it
    # see exactly these entries.
    private def literal_array_assignments(content : String, lexer : Noir::PhpLexer) : Hash(String, LiteralArray)
      arrays = {} of String => LiteralArray
      return arrays unless content.includes?("foreach")
      code = lexer.masked.join
      return arrays if code.matches?(DYNAMIC_VARS_RE)
      writes = variable_writes(code)
      scopes = function_scopes(content, lexer)
      code.scan(ASSIGNED_ARRAY_RE) do |m|
        name = m[1]
        next unless writes[name] == 1
        next if scopes.any?(&.includes?(m.begin(0)))
        next unless close = lexer.matching_delimiter(m.end(0) - 1)
        literal_array_entries(lexer.source(m.end(0)...close)).try { |entries| arrays[name] = LiteralArray.new(m.begin(0), entries) }
      end
      arrays
    end

    # The arrays a group closure body sees: the ones its `use (...)` lists
    # that are assigned before the group.
    private def arrays_captured_by(arrays : Hash(String, LiteralArray), uses : Array(String), at : Int32) : Hash(String, LiteralArray)
      visible = {} of String => LiteralArray
      uses.each do |name|
        next unless (array = arrays[name]?) && array.pos < at
        visible[name] = LiteralArray.new(-1, array.entries)
      end
      visible
    end

    # Bodies of every function, closure and class-like declaration in
    # `content`: their own variable scopes.
    private def function_scopes(content : String, lexer : Noir::PhpLexer) : Array(Range(Int32, Int32))
      scopes = [] of Range(Int32, Int32)
      masked = lexer.masked
      content.scan(SCOPE_RE) do |m|
        next unless lexer.in_code?(m.begin(0))
        i = m.end(0)
        depth = 0
        while i < masked.size
          c = masked[i]
          depth += 1 if c == '('
          depth -= 1 if c == ')'
          break if depth == 0 && (c == '{' || c == ';')
          i += 1
        end
        next unless i < masked.size && masked[i] == '{' && (close = lexer.matching_delimiter(i))
        scopes << ((i + 1)...close)
      end
      scopes
    end

    # The entries of a literal array's inner text, or nil when one is
    # anything the route scan cannot use verbatim (a call, a variable, a
    # nested options array, a spread).
    private def literal_array_entries(inner : String) : Array(LoopEntry)?
      parts = Noir::TopLevelSplit.split(inner, ',', ARRAY_SPLIT_RULES).reject(&.empty?)
      return if parts.empty? || parts.size > LoopBudget::MAX
      parts.map do |part|
        m = part.match(ARRAY_ENTRY_RE)
        value = m.try(&.[3].strip.gsub(/\s+/, " "))
        return unless m && value && value.matches?(ARRAY_VALUE_RE)
        LoopEntry.new(m[2]?, value)
      end
    end

    # Expand every outermost loop of `content` that registers routes over a
    # constant literal array, yielding each per-entry body (with where it
    # starts and the arrays it sees) for the route scan. A loop is expanded
    # whole or not at all: if one entry's routes still name a variable in
    # their path (an inner loop, or a variable the body computes), or the
    # budget runs out, the loop keeps the as-written scan. Returns each
    # expanded loop's body range and its routes.
    private def expand_route_loops(content : String, lexer : Noir::PhpLexer, arrays : Hash(String, LiteralArray),
                                   budget : LoopBudget, & : String, Int32, Hash(String, LiteralArray) -> Array(Endpoint)) : Array(Tuple(Range(Int32, Int32), Array(Endpoint)))
      expanded = [] of Tuple(Range(Int32, Int32), Array(Endpoint))
      return expanded unless content.includes?("foreach")
      scopes = function_scopes(content, lexer)
      outer = [] of Range(Int32, Int32)
      route_loops(content, lexer, arrays).each do |loop|
        # An inner loop is expanded with its outer one; one inside a
        # function or closure (a group body, a handler) belongs to that scope.
        next if outer.any?(&.includes?(loop.start)) || scopes.any?(&.includes?(loop.start))
        outer << (loop.body_start...loop.body_end)
        next unless budget.take(loop.entries.size)
        body_arrays = {} of String => LiteralArray
        arrays.each { |name, array| body_arrays[name] = LiteralArray.new(-1, array.entries) if array.pos < loop.start }
        routes = [] of Endpoint
        complete = loop.entries.all? do |entry|
          budget.unresolved = false
          routes.concat(yield substitute_loop_vars(loop.body, loop, entry), loop.body_start, body_arrays)
          !budget.unresolved?
        end
        expanded << {(loop.body_start...loop.body_end), routes} if complete
      end
      expanded
    end

    # Flag a per-entry body (or a group body inside one) whose own route
    # calls still interpolate a variable: an inner loop that was not
    # expanded, or a value the body computes. Expanded inner loops and
    # handler bodies are left out: they are not this scan's routes.
    private def flag_unresolved_route_args(content : String, lexer : Noir::PhpLexer, skip : Array(Range(Int32, Int32)), budget : LoopBudget) : Nil
      return if budget.unresolved? || !content.includes?('$')
      content.scan(UNRESOLVED_ROUTE_ARG_RE) do |m|
        at = m.begin(0)
        next if !lexer.in_code?(at) || skip.any?(&.includes?(at))
        budget.unresolved = true
        return
      end
    end

    # `foreach ($map as $key => $value) { … }` over a literal array (inline,
    # or one `arrays` holds that is assigned before the loop) whose body
    # registers routes and leaves the loop variables alone.
    private def route_loops(content : String, lexer : Noir::PhpLexer, arrays : Hash(String, LiteralArray)) : Array(RouteLoop)
      loops = [] of RouteLoop
      content.scan(FOREACH_RE) do |m|
        next unless lexer.in_code?(m.begin(0))
        open = m.end(0) - 1
        next unless close = lexer.matching_delimiter(open)
        next unless head = lexer.source((open + 1)...close).match(FOREACH_HEAD_RE)
        brace = close + 1
        while brace < content.size && lexer.masked[brace].whitespace?
          brace += 1
        end
        next unless brace < content.size && lexer.masked[brace] == '{' && (body_end = lexer.matching_delimiter(brace))
        iterable = head[1]
        entries = if iterable.starts_with?('$')
                    arrays[iterable.lchop('$')]?.try { |array| array.entries if array.pos < m.begin(0) }
                  else
                    inner = iterable.starts_with?('[') ? iterable[1...-1] : iterable.sub(/\Aarray\s*\(/, "").rchop(")")
                    literal_array_entries(inner)
                  end
        next unless entries
        next if head[2]? && entries.any? { |entry| entry.key.nil? } # `$k => $v` over a list: keys are ints
        body = lexer.source((brace + 1)...body_end)
        next unless body.includes?("Route::")
        next unless loop_vars_untouched?(lexer.masked[(brace + 1)...body_end].join, [head[2]?, head[3]].compact)
        loops << RouteLoop.new(m.begin(0), body, brace + 1, body_end, head[2]?, head[3], entries)
      end
      loops
    end

    # Whether the body (strings masked) only reads the loop variables: no
    # write, no closure parameter shadowing one, and no `continue`/`break`
    # that makes which entries register depend on the body's logic.
    private def loop_vars_untouched?(code : String, vars : Array(String)) : Bool
      return false if code.matches?(LOOP_CONTROL_RE) || code.matches?(DYNAMIC_VARS_RE)
      writes = variable_writes(code)
      return false if vars.any? { |var| writes[var] > 0 }
      code.scan(PARAM_LIST_RE).none? { |m| vars.any? { |var| m[1].matches?(/\$#{var}\b/) } }
    end

    # `body` with the loop variables replaced by one entry: in code, by the
    # entry's source (`$controller` -> `FooController::class`); inside a
    # double-quoted string, by the string value it interpolates (only a
    # string has one).
    private def substitute_loop_vars(body : String, loop : RouteLoop, entry : LoopEntry) : String
      lexer = Noir::PhpLexer.new(body, php_mode: true)
      key_source = entry.key.try { |key| "'#{key}'" }
      body.gsub(LOOP_VAR_USE_RE) do |whole, m|
        name = m[1]? || m[2]
        source = if name == loop.value_var
                   entry.value
                 elsif name == loop.key_var
                   key_source
                 end
        next whole unless source
        if lexer.in_code?(m.begin(0))
          m[1]? ? whole : source
        elsif (span = lexer.spans.find { |(kind, s, e)| kind == :string && s <= m.begin(0) && m.begin(0) < e }) && body[span[1]] == '"'
          source.match(STRING_LITERAL_RE).try(&.[2]) || whole
        else
          whole
        end
      end
    end
  end
end
