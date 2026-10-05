require "../utils/js_literal_scanner"
require "../utils/top_level_split"
require "./js_route_extractor"
require "../ext/tree_sitter/tree_sitter"

module Noir
  # Code-first Azure Functions HTTP triggers, which ship without a
  # `function.json`: C# `[HttpTrigger]` attributes (isolated worker and
  # in-process), Python v2 `@app.route` decorators and Node v4 `app.http(...)`
  # calls. Yields declarations only; the route prefix from `host.json` is the
  # analyzer's job.
  module AzureFunctionsExtractor
    extend self

    # `route` nil means "not declared": the host serves the trigger on the
    # function name. `methods` empty means every verb.
    record Trigger,
      name : String?,
      route : String?,
      methods : Array(String),
      auth_level : String?,
      line : Int32

    # Any binding trigger (`TimerTrigger`, `QueueTrigger`, ...): every function
    # has exactly one, so they delimit which `[Function]` belongs to which.
    CS_TRIGGER       = /\[\s*(?:[\w.]+\.)?(\w*)Trigger(?:Attribute)?\s*[(\]]/
    CS_NAMEOF        = /\Anameof\s*\(\s*(?:[\w.]+\.)?(\w+)\s*\)\z/
    CS_FUNCTION_NAME = /\[\s*(?:Function|FunctionName)(?:Attribute)?\s*\(\s*(?:@?"([^"]*)"|nameof\s*\(\s*(?:[\w.]+\.)?(\w+)\s*\))/

    CS_VERBATIM = /@"(?:[^"]|"")*"/

    PY_IMPORT    = /\bazure(?:\.|\s+import\s+)(?:durable_)?functions\b/
    PY_DECORATOR = /^[ \t]*@\w+\s*\.\s*route\s*\(/m
    PY_APP_CLASS = /(?:\A|\.)(FunctionApp|Blueprint|DFApp)\z/
    PY_METHOD    = /(["'])(\w+)\1|\bHttpMethod\s*\.\s*(\w+)/

    # `app` must come from `@azure/functions`: v3-model files import its types
    # next to an Express `app` whose routes are not Azure triggers.
    JS_APP_IMPORT = /\{[^}]*\bapp\b[^}]*\}\s*(?:from\s*|=\s*require\s*\(\s*)["']@azure\/functions["']/
    # `df.app.client.http(...)` is durable-functions' wrapper over `app.http`.
    JS_CALL        = /(?:(?<![\w$.])app|\bapp\s*\.\s*client)\s*\.\s*(http|get|post|put|patch|deleteRequest)\s*\(/
    JS_TYPE_SUFFIX = /\s+(?:satisfies|as)\s+[\w.<>]+\s*\z/
    JS_EXTENSIONS  = {".js", ".mjs", ".cjs", ".ts", ".mts", ".cts"}

    # Node v4 `trigger.http` fills in `['GET', 'POST']` when `methods` is
    # omitted; C# and Python leave it empty, which the host reads as any verb.
    JS_DEFAULT_METHODS = ["GET", "POST"]

    ARGS          = TopLevelSplit::Rules.new
    JS_ARGS       = TopLevelSplit::Rules.new(quotes: "\"'`")
    QUOTED        = /\A([rRuUbBfF@$]*)(["'`])((?:(?!\2)[^\\]|\\.)*)\2\z/m
    KEYWORD_ARG   = /\A(\w+)\s*[:=]\s*(.*)\z/m
    JS_KEY        = /\A["'`]?(\w+)["'`]?\s*:\s*(.*)\z/m
    STRING_TOKENS = /(["'`])((?:(?!\1)[^\\]|\\.)*)\1/

    # Whether the file declares at least one HTTP trigger in a code-first
    # programming model. A cheap substring gate runs before each regex.
    def code_first?(path : String, content : String) : Bool
      if path.ends_with?(".cs")
        content.includes?("HttpTrigger") && content.scan(CS_TRIGGER).any? { |m| m[1] == "Http" }
      elsif path.ends_with?(".py")
        content.includes?("azure") && content.matches?(PY_IMPORT) && content.matches?(PY_DECORATOR)
      elsif js_path?(path)
        js_app?(content) && content.matches?(JS_CALL)
      else
        false
      end
    end

    def extract(path : String, content : String) : Array(Trigger)
      if path.ends_with?(".cs")
        csharp(content)
      elsif path.ends_with?(".py")
        python(content)
      elsif js_path?(path)
        javascript(content)
      else
        [] of Trigger
      end
    end

    def csharp(content : String) : Array(Trigger)
      triggers = [] of Trigger
      # C# shares JS's `//` and `/* */` comments and double-quoted strings, so
      # the JS blanker keeps a commented-out function from being reported.
      # Verbatim strings are the exception: `@"C:\temp\"` ends on a backslash
      # the blanker would read as an escape, so swap those for `/` first.
      code = JSRouteExtractor.strip_js_comments(content.gsub(CS_VERBATIM, &.tr("\\", "/")))
      newlines = newline_offsets(code)

      names = [] of {Int32, String?}
      code.scan(CS_FUNCTION_NAME) { |m| names << {m.begin(0), m[1]? || m[2]?} }

      previous_trigger = -1
      code.scan(CS_TRIGGER) do |m|
        # The `[Function]` attribute of this method sits between the previous
        # trigger and this one; anything earlier belongs to another method.
        start = m.begin(0)
        name = names.reverse_each.find { |(pos, _)| pos > previous_trigger && pos < start }.try(&.[1])
        previous_trigger = start
        next unless m[1] == "Http"

        # A bare `[HttpTrigger]` takes every default.
        args = m[0].ends_with?('(') ? (call_args(code, m.end(0) - 1, ARGS) || next) : [] of String
        route = nil
        methods = [] of String
        auth_level = nil
        unresolved = false

        args.each do |arg|
          if kw = arg.match(KEYWORD_ARG)
            # Properties are `Route =`, constructor arguments `route:`.
            case kw[1].downcase
            when "route"
              value = kw[2].strip
              next if value == "null"
              route = csharp_string(value)
              unresolved = true unless route
            when "methods"
              kw[2].scan(STRING_TOKENS) { |s| methods << s[2].upcase }
            when "authlevel"
              auth_level = last_identifier(kw[2])
            end
          elsif value = literal(arg)
            methods << value.upcase
          elsif arg.includes?("AuthorizationLevel")
            auth_level = last_identifier(arg)
          end
        end
        # A route held in a constant cannot be resolved here, and the
        # function-name fallback would report a path the host never serves.
        next if unresolved

        triggers << Trigger.new(name, route, methods, auth_level.try(&.downcase), line_at(newlines, m))
      end

      triggers
    end

    def python(content : String) : Array(Trigger)
      triggers = [] of Trigger
      TreeSitter.parse_python(content) do |root|
        apps = python_apps(root, content)
        next if apps.empty?

        TreeSitter.walk(root) do |node|
          next unless TreeSitter.node_type(node) == "decorated_definition"
          python_definition(node, content, apps, triggers)
        end
      end
      triggers
    end

    def javascript(content : String) : Array(Trigger)
      triggers = [] of Trigger
      return triggers unless js_app?(content)
      code = JSRouteExtractor.strip_js_comments(content)
      newlines = newline_offsets(code)

      code.scan(JS_CALL) do |m|
        args = call_args(code, m.end(0) - 1, JS_ARGS) || next
        name = args[0]?.try { |v| literal(v) }
        verb = m[1]
        methods = verb == "http" ? JS_DEFAULT_METHODS.dup : [verb == "deleteRequest" ? "DELETE" : verb.upcase]
        route = nil
        auth_level = nil
        unresolved = false

        options = args[1]?.try(&.strip.sub(JS_TYPE_SUFFIX, "")) || ""
        if options.starts_with?('{') && options.ends_with?('}')
          TopLevelSplit.split(options[1...-1], ',', JS_ARGS).each do |entry|
            kw = entry.match(JS_KEY) || next
            case kw[1]
            when "route"
              route = literal(kw[2])
              unresolved = true unless route
            when "authLevel"
              auth_level = literal(kw[2])
            when "methods"
              next unless verb == "http"
              # Declared but not a literal array: any verb is the honest answer.
              methods = [] of String
              kw[2].scan(STRING_TOKENS) { |s| methods << s[2].upcase }
            end
          end
        elsif verb == "http"
          # Options held in a variable: the route is unknown.
          unresolved = true
        end
        next if unresolved

        triggers << Trigger.new(name, route, methods, auth_level, line_at(newlines, m))
      end

      triggers
    end

    # `"a/" + nameof(B)`: literals and `nameof` joined by `+`. Anything else
    # (a constant, a method call) is unresolved.
    private def csharp_string(expr : String) : String?
      String.build do |io|
        TopLevelSplit.split(expr, '+', ARGS).each do |part|
          if value = literal(part)
            io << value
          elsif nameof = part.match(CS_NAMEOF)
            io << nameof[1]
          else
            return
          end
        end
      end
    end

    # Receiver name => app-level `http_auth_level` for every
    # `FunctionApp` / `Blueprint` / `DFApp` assignment. Only decorators on
    # these count: a Flask app in the same module also spells its routes
    # `@app.route(...)`.
    private def python_apps(root : LibTreeSitter::TSNode, source : String) : Hash(String, String?)
      apps = {} of String => String?
      TreeSitter.walk(root) do |node|
        next unless TreeSitter.node_type(node) == "assignment"
        left = TreeSitter.field(node, "left")
        right = TreeSitter.field(node, "right")
        next unless left && right && TreeSitter.node_type(left) == "identifier" && TreeSitter.node_type(right) == "call"
        callee = TreeSitter.field(right, "function") || next
        klass = TreeSitter.node_text(callee, source).match(PY_APP_CLASS) || next
        positional, keywords = python_args(right, source)
        # Flask and Sanic blueprints take a name; Azure's takes none.
        next if klass[1] == "Blueprint" && !positional.empty?
        apps[TreeSitter.node_text(left, source)] = keywords["http_auth_level"]?.try { |v| last_identifier(v) }
      end
      apps
    end

    # One `def` and its decorator stack. `function_name` may sit above or
    # below `route`, so routes are emitted once the whole stack is read.
    private def python_definition(node : LibTreeSitter::TSNode, source : String,
                                  apps : Hash(String, String?), triggers : Array(Trigger))
      name = TreeSitter.field(node, "definition").try { |d| TreeSitter.field(d, "name") }.try { |n| TreeSitter.node_text(n, source) }
      routes = [] of {String, Array(String), Hash(String, String), Int32}

      TreeSitter.each_named_child(node) do |decorator|
        next unless TreeSitter.node_type(decorator) == "decorator"
        call = TreeSitter.first_named_child(decorator) || next
        next unless TreeSitter.node_type(call) == "call"
        function = TreeSitter.field(call, "function") || next
        next unless TreeSitter.node_type(function) == "attribute"
        receiver = TreeSitter.field(function, "object").try { |o| TreeSitter.node_text(o, source) }
        next unless receiver && apps.has_key?(receiver)

        positional, keywords = python_args(call, source)
        case TreeSitter.field(function, "attribute").try { |a| TreeSitter.node_text(a, source) }
        when "function_name"
          name = literal(keywords["name"]? || positional.first? || "") || name
        when "route"
          routes << {receiver, positional, keywords, TreeSitter.node_start_row(decorator) + 1}
        end
      end

      routes.each do |(receiver, positional, keywords, line)|
        route_arg = keywords["route"]? || positional.first?
        route = route_arg.try { |v| literal(v) }
        next if route.nil? && route_arg && route_arg != "None"

        methods = [] of String
        keywords["methods"]?.try &.scan(PY_METHOD) { |s| methods << (s[2]? || s[3]).upcase }
        auth_level = keywords["auth_level"]?.try { |v| literal(v) || last_identifier(v) } || apps[receiver]
        triggers << Trigger.new(name, route, methods, auth_level.try(&.downcase), line)
      end
    end

    # Source text of a call's positional and keyword arguments.
    private def python_args(call : LibTreeSitter::TSNode, source : String) : {Array(String), Hash(String, String)}
      positional = [] of String
      keywords = {} of String => String
      if args = TreeSitter.field(call, "arguments")
        TreeSitter.each_named_child(args) do |arg|
          case TreeSitter.node_type(arg)
          when "keyword_argument"
            key = TreeSitter.field(arg, "name")
            value = TreeSitter.field(arg, "value")
            keywords[TreeSitter.node_text(key, source)] = TreeSitter.node_text(value, source) if key && value
          when "comment"
          else
            positional << TreeSitter.node_text(arg, source)
          end
        end
      end
      {positional, keywords}
    end

    private def js_app?(content : String) : Bool
      return true if content.includes?("durable-functions")
      content.includes?("@azure/functions") && content.matches?(JS_APP_IMPORT)
    end

    private def js_path?(path : String) : Bool
      JS_EXTENSIONS.includes?(File.extname(path))
    end

    # Top-level arguments of the call whose `(` sits at char index `open`.
    private def call_args(code : String, open : Int32, rules : TopLevelSplit::Rules) : Array(String)?
      close = JSLiteralScanner.find_matching_paren(code, open) || return
      TopLevelSplit.split(code[(open + 1)...close], ',', rules)
    end

    # A string literal's value. An interpolated one (`$"{x}"`, `f"{x}"`,
    # `` `${x}` ``) is not a constant, so it reads as unresolved.
    private def literal(value : String) : String?
      m = value.strip.match(QUOTED) || return
      body = m[3]
      return if m[2] == "`" && body.includes?("${")
      return if m[1].matches?(/[$fF]/) && body.includes?('{')
      body
    end

    private def last_identifier(value : String) : String?
      value.scan(/\w+/).last?.try(&.[0])
    end

    # Byte offsets of every newline, so each match's line is a binary search
    # instead of a rescan from the top of the file.
    private def newline_offsets(code : String) : Array(Int32)
      offsets = [] of Int32
      code.to_slice.each_with_index { |byte, i| offsets << i if byte == '\n'.ord }
      offsets
    end

    private def line_at(newlines : Array(Int32), m : Regex::MatchData) : Int32
      (newlines.bsearch_index { |offset| offset >= m.byte_begin(0) } || newlines.size) + 1
    end
  end
end
