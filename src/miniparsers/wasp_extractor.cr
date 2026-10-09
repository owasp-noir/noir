require "../utils/top_level_split"
require "../utils/js_literal_scanner"
require "./js_route_extractor"

module Noir
  # Wasp (https://wasp.sh) app declarations.
  #
  # A Wasp app declares its HTTP surface in a config file rather than in
  # route calls, in one of three syntaxes:
  #
  # - The Wasp DSL (`main.wasp`, any `*.wasp` file up to Wasp 0.23):
  #   `api fooBar { fn: import { fooBar } from "@src/apis", httpRoute: (GET, "/foo/bar") }`
  # - The Wasp Spec (`main.wasp.ts` plus any `*.wasp.ts`, Wasp 0.24+,
  #   imported from `@wasp.sh/spec`): `api("GET", "/foo/bar", fooBar, { auth: false })`
  # - The preview TS config (Wasp 0.15–0.23, imported from `wasp-config`):
  #   `app.api("fooBar", { fn: { import: "fooBar", from: "@src/apis" }, httpRoute: { method: "GET", route: "/foo/bar" } })`
  #
  # All three describe the same declarations, so each parser fills the same
  # `Spec`. Mapping declarations to server routes is left to the analyzer.
  module WaspExtractor
    extend self

    JS_RULES = TopLevelSplit::Rules::JS

    # The handler a declaration points at: the exported name (`default` for
    # a default import) and the module specifier as written.
    record FnRef, name : String, from : String

    record Api, name : String, method : String, path : String, auth : Bool?, fn : FnRef?, line : Int32

    # `kind` is `query` or `action`.
    record Operation, kind : String, name : String, auth : Bool?, fn : FnRef?, line : Int32

    # A client-side page route.
    record PageRoute, name : String, path : String, auth_required : Bool, line : Int32

    # `name` is the Wasp operation key: get, getAll, create, update, delete.
    record CrudOperation, name : String, public : Bool, overridden : Bool, fn : FnRef?

    record Crud, name : String, entity : String, operations : Array(CrudOperation), line : Int32

    class Spec
      getter apis = [] of Api
      getter operations = [] of Operation
      getter routes = [] of PageRoute
      getter cruds = [] of Crud
      # `nil` while no `app` declaration was seen in the file.
      property auth_enabled : Bool? = nil
      property auth_methods = [] of String
      # Wasp Spec: `app({ auth: authConfig })` names an object declared
      # elsewhere (often another `*.wasp.ts`); the caller resolves it.
      property auth_ref : String? = nil
      property? app_declared = false
      # Line of the `app` declaration (or `app.auth(...)` call).
      property app_line : Int32? = nil

      def empty? : Bool
        apis.empty? && operations.empty? && routes.empty? && cruds.empty? && !app_declared?
      end
    end

    CRUD_OPERATIONS = %w[get getAll create update delete]

    # --- Wasp DSL ---------------------------------------------------------

    DSL_DECL       = /^[ \t]*(app|page|route|query|action|api|apiNamespace|crud|job|entity)\s+([A-Za-z_]\w*)\s*\{/m
    DSL_HTTP_ROUTE = /\A\(\s*([A-Za-z]+)\s*,\s*"([^"]*)"\s*\)\z/
    DSL_IMPORT     = /\Aimport\s+(?:\{\s*([A-Za-z_$][\w$]*)(?:\s+as\s+[A-Za-z_$][\w$]*)?\s*\}|([A-Za-z_$][\w$]*))\s+from\s+"([^"]+)"\z/

    def parse_dsl(content : String) : Spec
      spec = Spec.new
      code = strip_dsl(content)
      pages = Hash(String, Bool).new
      pending = [] of Tuple(String, String, String?, Int32)

      pos = 0
      while m = code.match(DSL_DECL, pos)
        open = m.end(0) - 1
        close = JSLiteralScanner.find_matching_brace(code, open)
        break unless close
        pos = close + 1
        entries = object_entries(code[(open + 1)...close])
        line = JSRouteExtractor.line_for_char_pos(code, m.begin(0) + (m[0].size - m[0].lstrip.size))
        name = m[2]

        case m[1]
        when "app"
          spec.app_declared = true
          spec.app_line = line
          if auth = entries["auth"]?
            spec.auth_enabled = true
            spec.auth_methods = auth_methods(auth)
          else
            spec.auth_enabled = false
          end
        when "api"
          route = entries["httpRoute"]?.try(&.match(DSL_HTTP_ROUTE))
          next unless route
          spec.apis << Api.new(name, route[1].upcase, route[2], bool_value(entries["auth"]?), dsl_import(entries["fn"]?), line)
        when "query", "action"
          spec.operations << Operation.new(m[1], name, bool_value(entries["auth"]?), dsl_import(entries["fn"]?), line)
        when "page"
          pages[name] = bool_value(entries["authRequired"]?) || false
        when "route"
          path = string_value(entries["path"]?)
          next unless path
          pending << {name, path, entries["to"]?, line}
        when "crud"
          if ops = entries["operations"]?.try { |v| object_body(v) }
            spec.cruds << Crud.new(name, entries["entity"]? || "", crud_operations(ops) { |v| dsl_import(v) }, line)
          end
        end
      end

      pending.each do |route_name, route_path, to, route_line|
        spec.routes << PageRoute.new(route_name, route_path, to.try { |page| pages[page]? } || false, route_line)
      end
      spec
    end

    private def dsl_import(value : String?) : FnRef?
      m = value.try(&.match(DSL_IMPORT))
      return unless m
      FnRef.new(m[1]? || "default", m[3])
    end

    # Blanks DSL comments and `{=json ... json=}` / `{=psl ... psl=}`
    # quoted blocks (keeping newlines, so line numbers hold). Strings are
    # double-quoted only.
    def strip_dsl(content : String) : String
      String.build(content.bytesize) do |io|
        reader = Char::Reader.new(content)
        state = :code
        quoter = ""
        while reader.has_next?
          char = reader.current_char
          nxt = reader.peek_next_char
          case state
          when :code
            if char == '"'
              state = :string
              io << char
            elsif char == '/' && nxt == '/'
              state = :line_comment
              io << ' '
            elsif char == '/' && nxt == '*'
              state = :block_comment
              io << ' '
            elsif char == '{' && nxt == '='
              # `{=tag` ... `tag=}`
              tag = String.build do |t|
                r = reader.pos + 2
                while r < content.bytesize && (c = content.byte_at(r).unsafe_chr) && (c.ascii_letter? || c.ascii_number?)
                  t << c
                  r += 1
                end
              end
              state = :quoter
              quoter = "#{tag}=}"
              io << ' '
            else
              io << char
            end
          when :string
            io << char
            if char == '\\'
              reader.next_char
              io << reader.current_char if reader.has_next?
            elsif char == '"' || char == '\n'
              state = :code
            end
          when :line_comment
            if char == '\n'
              state = :code
              io << char
            else
              io << ' '
            end
          when :block_comment
            if char == '*' && nxt == '/'
              io << "  "
              reader.next_char
              state = :code
            else
              io << (char == '\n' ? '\n' : ' ')
            end
          when :quoter
            if !quoter.empty? && content.byte_slice(reader.pos, quoter.bytesize) == quoter
              (quoter.size - 1).times do
                io << ' '
                reader.next_char
              end
              io << ' '
              state = :code
            else
              io << (char == '\n' ? '\n' : ' ')
            end
          end
          reader.next_char
        end
      end
    end

    # --- Wasp Spec (`@wasp.sh/spec`, Wasp 0.24+) ---------------------------

    SPEC_IMPORT   = /import\s*(\{[^}]*\}|\*\s*as\s+[A-Za-z_$][\w$]*)\s*from\s*['"]@wasp\.sh\/spec['"]/
    SPEC_CALLEES  = %w[app api query action route crud page]
    TS_IMPORT     = /import\s+(?:type\s+)?((?:[A-Za-z_$][\w$]*\s*,?\s*)?(?:\{[^}]*\})?)\s*from\s*['"]([^'"]+)['"]/
    IDENTIFIER    = /\A[A-Za-z_$][\w$]*\z/
    STRING_LIT    = /\A(["'`])(.*)\1\z/m
    TS_TYPE_SPLIT = /\s*:\s*/

    def spec_module?(content : String) : Bool
      content.includes?("@wasp.sh/spec") && content.matches?(SPEC_IMPORT)
    end

    def parse_spec(content : String) : Spec
      spec = Spec.new
      code = JSRouteExtractor.strip_js_comments(content)
      callees = spec_callee_names(code)
      return spec if callees.empty?
      refs = import_refs(code)

      each_call(code, callees) do |kind, args, pos|
        line = JSRouteExtractor.line_for_char_pos(code, pos)
        case kind
        when "app"
          config = args[0]?.try { |a| object_body(a) }
          next unless config
          spec.app_declared = true
          spec.app_line = line
          entries = object_entries(config)
          auth = entries["auth"]?
          if auth.nil? || auth == "undefined" || auth == "null"
            spec.auth_enabled = false
          else
            spec.auth_enabled = true
            if auth.matches?(IDENTIFIER)
              spec.auth_ref = auth
            else
              spec.auth_methods = auth_methods(auth)
            end
          end
        when "api"
          method = string_value(args[0]?)
          path = string_value(args[1]?)
          handler = args[2]?
          next unless method && path && handler
          config = object_entries(args[3]?.try { |a| object_body(a) } || "")
          spec.apis << Api.new(ref_name(handler), method.upcase, path, bool_value(config["auth"]?), refs[handler]?, line)
        when "query", "action"
          handler = args[0]?
          next unless handler && handler.matches?(IDENTIFIER)
          config = object_entries(args[1]?.try { |a| object_body(a) } || "")
          spec.operations << Operation.new(kind, ref_name(handler), bool_value(config["auth"]?), refs[handler]?, line)
        when "route"
          name = string_value(args[0]?)
          path = string_value(args[1]?)
          next unless name && path
          spec.routes << PageRoute.new(name, path, spec_page_auth_required(code, args[2]?, callees), line)
        when "crud"
          name = string_value(args[0]?)
          ops = args[2]?.try { |a| object_body(a) }
          next unless name && ops
          spec.cruds << Crud.new(name, string_value(args[1]?) || "", crud_operations(ops) { |v| refs[v]? }, line)
        end
      end
      spec
    end

    # Local name → canonical `@wasp.sh/spec` constructor. Named imports may
    # be aliased (`api as waspApi`); a namespace import (`* as w`) makes
    # every constructor reachable as `w.api(...)`.
    private def spec_callee_names(code : String) : Hash(String, String)
      names = Hash(String, String).new
      code.scan(SPEC_IMPORT) do |m|
        clause = m[1]
        if clause.starts_with?('{')
          clause.strip.lchop('{').rchop('}').split(',').each do |spec|
            parts = spec.strip.sub(/\Atype\s+/, "").split(/\s+as\s+/)
            canonical = parts[0].strip
            next unless SPEC_CALLEES.includes?(canonical)
            names[(parts[1]? || canonical).strip] = canonical
          end
        elsif ns = clause.match(/\*\s*as\s+([A-Za-z_$][\w$]*)/)
          SPEC_CALLEES.each { |callee| names["#{ns[1]}.#{callee}"] = callee }
        end
      end
      names
    end

    # `page(X, { authRequired: true })` inline, or the name of a
    # `const x = page(...)` declared in the same file.
    private def spec_page_auth_required(code : String, arg : String?, callees : Hash(String, String)) : Bool
      return false unless arg
      expr = arg
      if arg.matches?(IDENTIFIER)
        decl = code.match(/\b(?:const|let|var)\s+#{Regex.escape(arg)}\b[^=]*=\s*/)
        return false unless decl
        expr = code[decl.end(0)..]
      end
      page_names = callees.select { |_, canonical| canonical == "page" }.keys
      page_names.each do |local|
        next unless expr.starts_with?(local)
        open = expr.index('(', local.size)
        next unless open && expr[local.size...open].strip.empty?
        close = JSLiteralScanner.find_matching_paren(expr, open)
        next unless close
        args = TopLevelSplit.split(expr[(open + 1)...close], ',', JS_RULES)
        config = object_entries(args[1]?.try { |a| object_body(a) } || "")
        return bool_value(config["authRequired"]?) || false
      end
      false
    end

    # --- Preview TS config (`wasp-config`, Wasp 0.15-0.23) -----------------

    CONFIG_IMPORT = /from\s*['"]wasp-config['"]/
    CONFIG_APP    = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*new\s+App\s*\(/

    def config_module?(content : String) : Bool
      content.includes?("wasp-config") && content.matches?(CONFIG_IMPORT)
    end

    def parse_config(content : String) : Spec
      spec = Spec.new
      code = JSRouteExtractor.strip_js_comments(content)
      receivers = code.scan(CONFIG_APP).map { |m| m[1] }
      return spec if receivers.empty?
      callees = Hash(String, String).new
      receivers.each do |recv|
        %w[api query action route page crud auth].each { |kind| callees["#{recv}.#{kind}"] = kind }
      end
      spec.app_declared = true
      spec.auth_enabled = false

      pages = Hash(String, Bool).new
      pending = [] of Tuple(String, String, String?, Int32)
      each_call(code, callees) do |kind, args, pos|
        line = JSRouteExtractor.line_for_char_pos(code, pos)
        name = string_value(args[0]?)
        config = args[1]?.try { |a| object_body(a) }
        case kind
        when "auth"
          if body = args[0]?.try { |a| object_body(a) }
            spec.auth_enabled = true
            spec.app_line = line
            spec.auth_methods = auth_methods("{#{body}}")
          end
          next
        end
        next unless name && config
        entries = object_entries(config)
        case kind
        when "api"
          route = entries["httpRoute"]?.try { |v| object_body(v) }.try { |v| object_entries(v) }
          next unless route
          method = string_value(route["method"]?)
          path = string_value(route["route"]?)
          next unless method && path
          spec.apis << Api.new(name, method.upcase, path, bool_value(entries["auth"]?), config_fn(entries["fn"]?), line)
        when "query", "action"
          spec.operations << Operation.new(kind, name, bool_value(entries["auth"]?), config_fn(entries["fn"]?), line)
        when "page"
          required = bool_value(entries["authRequired"]?) || false
          pages[name] = required
          # `const loginPage = app.page(...)`: routes point at the variable.
          if decl = code[0...pos].match(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*\z/)
            pages[decl[1]] = required
          end
        when "route"
          path = string_value(entries["path"]?)
          next unless path
          to = entries["to"]?
          to = string_value(to) || to
          pending << {name, path, to, line}
        when "crud"
          if ops = entries["operations"]?.try { |v| object_body(v) }
            spec.cruds << Crud.new(name, string_value(entries["entity"]?) || "", crud_operations(ops) { |v| config_fn(v) }, line)
          end
        end
      end

      pending.each do |name, path, to, line|
        spec.routes << PageRoute.new(name, path, to.try { |page| pages[page]? } || false, line)
      end
      spec
    end

    # `{ import: "x", from: "@src/y" }` / `{ importDefault: "X", from: ... }`.
    private def config_fn(value : String?) : FnRef?
      body = value.try { |v| object_body(v) }
      return unless body
      entries = object_entries(body)
      from = string_value(entries["from"]?)
      return unless from
      if name = string_value(entries["import"]?)
        FnRef.new(name, from)
      elsif entries.has_key?("importDefault")
        FnRef.new("default", from)
      end
    end

    # --- Shared helpers ---------------------------------------------------

    # `auth: { methods: { usernameAndPassword: {}, google: {} } }` → the
    # enabled method keys.
    def auth_methods(auth_value : String) : Array(String)
      body = object_body(auth_value)
      return [] of String unless body
      methods = object_entries(body)["methods"]?.try { |v| object_body(v) }
      return [] of String unless methods
      object_entries(methods).keys
    end

    # The object literal bound to `name` (`const name: Auth = { ... }`),
    # for an `app({ auth: name })` declared in another file.
    def object_literal_for(content : String, name : String) : String?
      code = JSRouteExtractor.strip_js_comments(content)
      m = code.match(/\b(?:const|let|var)\s+#{Regex.escape(name)}\b[^=;]*=\s*\{/)
      return unless m
      open = m.end(0) - 1
      close = JSLiteralScanner.find_matching_brace(code, open)
      return unless close
      code[open..close]
    end

    # Local name → handler reference for every import in a Wasp Spec file
    # (`import { a, b as c } from "./src/x" with { type: "ref" }`,
    # `import D from "./src/d" with { type: "ref" }`).
    private def import_refs(code : String) : Hash(String, FnRef)
      refs = Hash(String, FnRef).new
      code.scan(TS_IMPORT) do |m|
        clause = m[1].strip
        from = m[2]
        next if clause.empty? || from == "@wasp.sh/spec"
        if default = clause.match(/\A([A-Za-z_$][\w$]*)/)
          refs[default[1]] = FnRef.new("default", from)
        end
        if named = clause.match(/\{([^}]*)\}/)
          named[1].split(',').each do |spec|
            parts = spec.strip.sub(/\Atype\s+/, "").split(/\s+as\s+/)
            imported = parts[0].strip
            next if imported.empty?
            refs[(parts[1]? || imported).strip] = FnRef.new(imported, from)
          end
        end
      end
      refs
    end

    # Wasp names a Spec declaration after the referenced import.
    private def ref_name(expr : String) : String
      expr.split('.').last.strip
    end

    private def crud_operations(body : String, & : String -> FnRef?) : Array(CrudOperation)
      operations = [] of CrudOperation
      object_entries(body).each do |key, value|
        next unless CRUD_OPERATIONS.includes?(key)
        options = object_entries(object_body(value) || "")
        override = options["overrideFn"]?
        operations << CrudOperation.new(key, bool_value(options["isPublic"]?) || false, !override.nil?, override.try { |v| yield v })
      end
      operations
    end

    # Yields `(constructor, args, start)` for each call to a name in
    # `callees` (local name → canonical constructor), skipping member
    # calls such as `foo.api(` unless the dotted name itself is listed.
    private def each_call(code : String, callees : Hash(String, String), & : String, Array(String), Int32 ->)
      return if callees.empty?
      pattern = Regex.union(callees.keys.sort_by!(&.size).reverse!.map { |name| /(?<![\w$.])#{Regex.escape(name)}\s*\(/ })
      pos = 0
      while m = code.match(pattern, pos)
        open = m.end(0) - 1
        name = m[0].rchop('(').strip
        pos = open + 1
        canonical = callees[name]?
        next unless canonical
        close = JSLiteralScanner.find_matching_paren(code, open)
        next unless close
        yield canonical, TopLevelSplit.split(code[(open + 1)...close], ',', JS_RULES), m.begin(0)
      end
    end

    # Top-level `key: value` entries of an object literal body (the text
    # between its braces). Shorthand entries map a key to itself; spreads
    # are skipped.
    def object_entries(body : String) : Hash(String, String)
      entries = Hash(String, String).new
      TopLevelSplit.split(body, ',', JS_RULES).each do |entry|
        next if entry.starts_with?("...")
        if m = entry.match(/\A(?:"([^"]+)"|'([^']+)'|([A-Za-z_$][\w$]*))\s*:\s*(.*)\z/m)
          entries[m[1]? || m[2]? || m[3]] = m[4].strip
        elsif entry.matches?(IDENTIFIER)
          entries[entry] = entry
        end
      end
      entries
    end

    # The text between the braces of an object literal, or nil when the
    # value is not one. Trailing TS `as X` / `satisfies X` are tolerated.
    def object_body(value : String) : String?
      text = value.strip.sub(/\s+(?:as|satisfies)\s+[\w$.<>, ]+\z/, "")
      return unless text.starts_with?('{')
      close = JSLiteralScanner.find_matching_brace(text, 0)
      return unless close
      text[1...close]
    end

    def string_value(value : String?) : String?
      return unless value
      m = value.strip.match(STRING_LIT)
      return unless m
      return if m[1] == "`" && m[2].includes?("${")
      # `"a" + "b"` is an expression, not one literal.
      return if m[2].gsub(/\\./, "").includes?(m[1])
      m[2]
    end

    def bool_value(value : String?) : Bool?
      case value.try(&.strip)
      when "true"  then true
      when "false" then false
      end
    end

    # --- Handlers ---------------------------------------------------------

    # A handler's parameter list and body text, plus the 1-based line of
    # its declaration.
    record Handler, params : String, body : String, line : Int32

    # Finds the exported function `name` (`default` for the default export)
    # in a handler module: `export const x = async (args, ctx) => {...}`,
    # `export function x(req, res) {...}`, `export default async function`.
    def handler(content : String, name : String) : Handler?
      code = JSRouteExtractor.strip_js_comments(content)
      if name == "default"
        if m = code.match(/\bexport\s+default\s+(?:async\s+)?function\b[^(]*\(/)
          return function_at(code, m.end(0) - 1, m.begin(0))
        end
        if m = code.match(/\bexport\s+default\s+([A-Za-z_$][\w$]*)\s*;?\s*$/m)
          return handler_named(code, m[1])
        end
        if m = code.match(/\bexport\s+default\s+(?:async\s*)?(?=\(|[A-Za-z_$][\w$]*\s*=>)/)
          return arrow_at(code, m.end(0), m.begin(0))
        end
        return
      end
      handler_named(code, name)
    end

    private def handler_named(code : String, name : String) : Handler?
      escaped = Regex.escape(name)
      if m = code.match(/\b(?:async\s+)?function\s*\*?\s*#{escaped}\s*(?:<[^>{}()]*>)?\s*\(/)
        return function_at(code, m.end(0) - 1, m.begin(0))
      end
      if m = code.match(/\b(?:const|let|var)\s+#{escaped}\b\s*(?::[^=]+?)?=(?![=>])\s*/)
        return arrow_at(code, m.end(0), m.begin(0))
      end
      nil
    end

    private def function_at(code : String, open : Int32, decl : Int32) : Handler?
      close = JSLiteralScanner.find_matching_paren(code, open)
      return unless close
      brace = code.index('{', close)
      return unless brace
      body_close = JSLiteralScanner.find_matching_brace(code, brace) || code.size - 1
      Handler.new(code[(open + 1)...close], code[(brace + 1)...body_close], JSRouteExtractor.line_for_char_pos(code, decl))
    end

    # From just after `=` (and any `async`): `(a, b) => {...}`, `a => {...}`
    # or `async function (a, b) {...}`.
    private def arrow_at(code : String, start : Int32, decl : Int32) : Handler?
      rest_start = skip_space(code, start)
      # `(async (args, ctx) => {...}) satisfies GetTasks`: a wrapping paren
      # opens on another function, never on a parameter.
      loop do
        if code[rest_start]? == '(' && code.match(/\G\(\s*(?:\(|async\b|function\b)/, rest_start)
          rest_start = skip_space(code, rest_start + 1)
        elsif code.match(/\Gasync\b/, rest_start)
          rest_start = skip_space(code, rest_start + 5)
        else
          break
        end
      end
      if code.match(/\Gfunction\b/, rest_start)
        open = code.index('(', rest_start)
        return unless open
        return function_at(code, open, decl)
      end
      if code[rest_start]? == '('
        close = JSLiteralScanner.find_matching_paren(code, rest_start)
        return unless close
        params = code[(rest_start + 1)...close]
        after = close + 1
      elsif m = code.match(/\G([A-Za-z_$][\w$]*)\s*=>/, rest_start)
        params = m[1]
        after = m.begin(0) + m[1].size
      else
        return
      end
      # Only a return type annotation may sit between `)` and `=>`.
      arrow = code.match(/\G\s*(?::[^=;{}]*(?:\{[^{}]*\}[^=;{}]*)*)?=>/, after)
      return unless arrow
      body_start = skip_space(code, arrow.end(0))
      body = if code[body_start]? == '{'
               body_close = JSLiteralScanner.find_matching_brace(code, body_start) || code.size - 1
               code[(body_start + 1)...body_close]
             else
               code[body_start...(code.index('\n', body_start) || code.size)]
             end
      Handler.new(params, body, JSRouteExtractor.line_for_char_pos(code, decl))
    end

    private def skip_space(code : String, pos : Int32) : Int32
      while pos < code.size && code[pos].whitespace?
        pos += 1
      end
      pos
    end

    # The fields an operation reads from its first argument (`args`):
    # destructured in the signature (`({ id, title }, context)`), or read
    # as `args.x` / `const { x } = args` in the body.
    def operation_args(handler : Handler) : Array(String)
      names = [] of String
      first = TopLevelSplit.split(handler.params, ',', JS_RULES).first?
      return names unless first
      if first.starts_with?('{')
        close = JSLiteralScanner.find_matching_brace(first, 0)
        return names unless close
        destructured_names(first[1...close], names)
      else
        arg = first.split(TS_TYPE_SPLIT, 2).first.strip.lchop("...")
        return names unless arg.matches?(IDENTIFIER) && arg != "_"
        escaped = Regex.escape(arg)
        handler.body.scan(/(?:const|let|var)\s*\{([^}]*)\}\s*=\s*#{escaped}\b(?!\s*\.)/) { |m| destructured_names(m[1], names) }
        handler.body.scan(/(?<![\w$.])#{escaped}\??\.([A-Za-z_$][\w$]*)/) { |m| names << m[1] unless names.includes?(m[1]) }
      end
      names
    end

    private def destructured_names(list : String, names : Array(String))
      TopLevelSplit.split(list, ',', JS_RULES).each do |part|
        key = part.split(/[:=]/, 2).first.strip.lchop("...")
        next unless key.matches?(IDENTIFIER)
        names << key unless names.includes?(key)
      end
    end
  end
end
