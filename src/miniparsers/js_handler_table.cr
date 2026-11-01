require "../ext/tree_sitter/tree_sitter"
require "./extraction_result_cache"
require "./js_callee_extractor"

module Noir
  # The handler functions of one JS/TS module, read off the syntax tree:
  # what it exports (`export function GET`, `export const GET = ...`,
  # `export { local as GET }`, CommonJS `exports.GET = ...`), what it
  # default-exports, the top-level functions it declares, and the inline
  # `config` object. Each function carries its parameter text, its body
  # (block contents or a bare expression), its lines and, on request, its
  # callees.
  #
  # One parse per file serves every lookup, so the file-routed adapters
  # (Next.js, Cloudflare Pages, Vercel, Netlify, Medusa) do not slice
  # bodies with brace counting: a return type `Promise<{ ok: true }>`, a
  # `${ { a: 1 } }` template or a `}` inside a regex literal cannot move
  # a body boundary on a tree.
  module JSHandlerTable
    extend self

    # `line` is the statement that declares or exports the function;
    # `body_line` is where the body starts (the `{` of a block). `block` is
    # false for an expression-bodied arrow. `direct` is false when the
    # function was reached through a wrapper call (`withAuth(handler)`) or
    # is unresolved (empty params and body).
    record Fn, params : String, body : String, line : Int32, body_line : Int32,
      block : Bool, direct : Bool, callees : Array(JSCalleeExtractor::Entry),
      methods : Array(String) = EMPTY_METHODS

    class Table
      getter exports = {} of String => Fn
      getter locals = {} of String => Fn
      # Members of an exported object literal (`export const handler = { GET() {} }`,
      # also `define.handlers({...})`), by export name. A member that is not a
      # function (`GET: 5`) is nil: the key is still there.
      getter objects = {} of String => Hash(String, Fn?)
      property default : Fn?
      # The inline `config` object's string values by key; a key whose value
      # is not a string literal or an array of them maps to [].
      property config : Hash(String, Array(String))?
      # Every name the module exports, in any form (`export const { A } = f()`,
      # `export { a as B } from "./x"` included). A name here without an
      # `exports` entry is exported but has no function this reader can open.
      getter export_names = Set(String).new
      # The file did not parse cleanly; the tables may be incomplete.
      property? parse_error = false
    end

    EMPTY_CALLEES     = [] of JSCalleeExtractor::Entry
    EMPTY_METHODS     = [] of String
    KNOWN_METHODS     = Set{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}
    METHOD_PROPERTIES = Set{"method", "httpMethod"}
    MAX_RESOLVE       = 4
    FUNCTION_TYPES    = Set{"function_declaration", "generator_function_declaration", "function_expression", "generator_function", "arrow_function"}

    @@memo = Hash(UInt64, Table).new
    @@mutex = Mutex.new

    Noir::ExtractionResultCache.register_clearer do
      @@mutex.synchronize { @@memo.clear }
    end

    # The module's table. `callees` also records each function's callees
    # (a separate cache entry, so scans that do not want them do not pay).
    def for(source : String, path : String, callees : Bool = false) : Table
      key = Noir::ExtractionResultCache.key(source, "js_handler_table", path, callees ? "c" : "n")
      Noir::ExtractionResultCache.fetch(@@memo, key, @@mutex) { build(source, path, callees) }
    end

    private def build(source : String, path : String, callees : Bool) : Table
      table = Table.new
      Noir::TreeSitter.parse_js_family(source, path) do |root|
        table.parse_error = Noir::TreeSitter.node_has_error?(root)
        Reader.new(source, path, callees, table).read(root)
      end
      table
    rescue
      Table.new.tap(&.parse_error = true)
    end

    private class Reader
      alias Node = LibTreeSitter::TSNode

      def initialize(@source : String, @path : String, @callees : Bool, @table : Table)
        @decl_fns = {} of String => Tuple(Node, Int32)    # function declarations
        @decl_values = {} of String => Tuple(Node, Int32) # const/let/var initializers
      end

      def read(root : Node) : Nil
        statements = [] of Node
        Noir::TreeSitter.each_named_child(root) { |child| statements << child }
        statements.each { |statement| collect(statement) }
        @decl_fns.each { |name, (node, line)| @table.locals[name] = fn_from(node, line, true) }
        @decl_values.each do |name, (node, line)|
          next if @table.locals.has_key?(name)
          if fn = value_fn(node, line, 0)
            @table.locals[name] = fn
          end
        end
        statements.each { |statement| register(statement) }
      end

      # Declarations first, so exports can point at a local declared later.
      private def collect(statement : Node) : Nil
        line = Noir::TreeSitter.node_start_row(statement) + 1
        node = statement
        if type(statement) == "export_statement"
          node = Noir::TreeSitter.field(statement, "declaration") || return
        end
        case type(node)
        when "function_declaration", "generator_function_declaration"
          if name = Noir::TreeSitter.field(node, "name")
            @decl_fns[text(name)] ||= {node, line}
          end
        when "lexical_declaration", "variable_declaration"
          Noir::TreeSitter.each_named_child(node) do |declarator|
            next unless type(declarator) == "variable_declarator"
            name = Noir::TreeSitter.field(declarator, "name")
            value = Noir::TreeSitter.field(declarator, "value")
            next unless name && value && type(name) == "identifier"
            @decl_values[text(name)] ||= {Noir::TreeSitter.unwrap_expression(value), line}
          end
        end
      end

      private def register(statement : Node) : Nil
        line = Noir::TreeSitter.node_start_row(statement) + 1
        case type(statement)
        when "export_statement"
          register_export(statement, line)
        when "expression_statement"
          register_commonjs(statement, line)
        end
      end

      private def register_export(statement : Node, line : Int32) : Nil
        record_export_names(statement)
        if default_export?(statement)
          node = Noir::TreeSitter.field(statement, "value") || Noir::TreeSitter.field(statement, "declaration")
          if node
            node = Noir::TreeSitter.unwrap_expression(node)
            @table.default ||= value_fn(node, line, 0)
            record_config_property(node)
          end
          return
        end

        if declaration = Noir::TreeSitter.field(statement, "declaration")
          case type(declaration)
          when "function_declaration", "generator_function_declaration"
            if name = Noir::TreeSitter.field(declaration, "name")
              @table.exports[text(name)] ||= fn_from(declaration, line, true)
            end
          when "lexical_declaration", "variable_declaration"
            Noir::TreeSitter.each_named_child(declaration) do |declarator|
              next unless type(declarator) == "variable_declarator"
              name = Noir::TreeSitter.field(declarator, "name")
              value = Noir::TreeSitter.field(declarator, "value")
              next unless name && value && type(name) == "identifier"
              value = Noir::TreeSitter.unwrap_expression(value)
              export_name = text(name)
              if export_name == "config" && type(value) == "object"
                @table.config ||= config_values(value)
              end
              if fn = value_fn(value, line, 0)
                @table.exports[export_name] ||= fn
              end
              if members = object_members(value, line)
                @table.objects[export_name] ||= members
              end
            end
          end
        elsif !Noir::TreeSitter.field(statement, "source")
          Noir::TreeSitter.each_named_child(statement) do |clause|
            next unless type(clause) == "export_clause"
            Noir::TreeSitter.each_named_child(clause) do |specifier|
              next unless type(specifier) == "export_specifier"
              local = Noir::TreeSitter.field(specifier, "name") || next
              exported = Noir::TreeSitter.field(specifier, "alias") || local
              fn = @table.locals[text(local)]? || next
              if text(exported) == "default"
                @table.default ||= fn
              else
                @table.exports[text(exported)] ||= fn
              end
            end
          end
        end
      end

      private def record_export_names(statement : Node) : Nil
        if declaration = Noir::TreeSitter.field(statement, "declaration")
          case type(declaration)
          when "function_declaration", "generator_function_declaration"
            Noir::TreeSitter.field(declaration, "name").try { |name| @table.export_names << text(name) }
          when "lexical_declaration", "variable_declaration"
            Noir::TreeSitter.each_named_child(declaration) do |declarator|
              next unless type(declarator) == "variable_declarator"
              name = Noir::TreeSitter.field(declarator, "name") || next
              if type(name) == "identifier"
                @table.export_names << text(name)
              else
                Noir::TreeSitter.walk(name) do |node|
                  case type(node)
                  when "shorthand_property_identifier_pattern"
                    @table.export_names << text(node)
                  when "pair_pattern"
                    Noir::TreeSitter.field(node, "value").try { |value| @table.export_names << text(value) if type(value) == "identifier" }
                  end
                end
              end
            end
          end
        end
        Noir::TreeSitter.each_named_child(statement) do |clause|
          next unless type(clause) == "export_clause"
          Noir::TreeSitter.each_named_child(clause) do |specifier|
            next unless type(specifier) == "export_specifier"
            exported = Noir::TreeSitter.field(specifier, "alias") || Noir::TreeSitter.field(specifier, "name")
            @table.export_names << text(exported).strip("'\"") if exported
          end
        end
      end

      # `exports.GET = ...`, `module.exports.GET = ...`, `module.exports = ...`.
      private def register_commonjs(statement : Node, line : Int32) : Nil
        assignment = Noir::TreeSitter.first_named_child(statement) || return
        return unless type(assignment) == "assignment_expression"
        left = Noir::TreeSitter.field(assignment, "left") || return
        right = Noir::TreeSitter.field(assignment, "right") || return
        return unless type(left) == "member_expression"
        right = Noir::TreeSitter.unwrap_expression(right)
        target = text(left).gsub(/\s+/, "")
        if target == "module.exports"
          @table.default ||= value_fn(right, line, 0)
          record_config_property(right)
        elsif (property = Noir::TreeSitter.field(left, "property")) &&
              (object = Noir::TreeSitter.field(left, "object")) &&
              {"exports", "module.exports"}.includes?(text(object).gsub(/\s+/, ""))
          if fn = value_fn(right, line, 0)
            @table.exports[text(property)] ||= fn
          end
        end
      end

      # The value of an export or declaration as a handler; nil when it is
      # not something that can serve a request.
      private def value_fn(node : Node, line : Int32, depth : Int32) : Fn?
        return if depth > MAX_RESOLVE
        node = Noir::TreeSitter.unwrap_expression(node)
        kind = type(node)
        return fn_from(node, line, true) if FUNCTION_TYPES.includes?(kind)

        case kind
        when "object"
          # `export default { fetch(req, ctx) {...} }` / `{ fetch: handler }`
          Noir::TreeSitter.each_named_child(node) do |member|
            case type(member)
            when "method_definition"
              name = Noir::TreeSitter.field(member, "name")
              return fn_from(member, line, true) if name && text(name) == "fetch"
            when "pair"
              key = Noir::TreeSitter.field(member, "key")
              value = Noir::TreeSitter.field(member, "value")
              return value_fn(value, line, depth + 1) if key && value && text(key) == "fetch"
            end
          end
          nil
        when "array"
          # Cloudflare middleware chains: `[auth, handler]` serve the last.
          last = nil.as(Node?)
          Noir::TreeSitter.each_named_arg(node) { |element| last = element }
          if last && type(last) == "identifier"
            local_fn(text(last), depth + 1) || empty_fn(line)
          else
            empty_fn(line)
          end
        when "call_expression"
          wrapped_fn(node, line, depth)
        when "identifier"
          local_fn(text(node), depth + 1) || empty_fn(line)
        end
      end

      # Members of an object literal, or of the one handed to
      # `define.handlers(...)` (Fresh 2).
      private def object_members(node : Node, line : Int32) : Hash(String, Fn?)?
        if type(node) == "call_expression"
          function = Noir::TreeSitter.field(node, "function")
          return unless function && text(function) == "define.handlers"
          args = Noir::TreeSitter.field(node, "arguments") || return
          node = Noir::TreeSitter.first_named_arg(args) || return
          node = Noir::TreeSitter.unwrap_expression(node)
        end
        return unless type(node) == "object"

        members = {} of String => Fn?
        Noir::TreeSitter.each_named_child(node) do |member|
          member_line = Noir::TreeSitter.node_start_row(member) + 1
          case type(member)
          when "method_definition"
            name = Noir::TreeSitter.field(member, "name") || next
            members[text(name).strip("'\"")] ||= fn_from(member, member_line, true)
          when "pair"
            key = Noir::TreeSitter.field(member, "key") || next
            value = Noir::TreeSitter.field(member, "value") || next
            members[text(key).strip("'\"")] ||= value_fn(value, member_line, 0)
          end
        end
        members
      end

      # A wrapper call (`withAuth(handler)`, `schedule("@daily", fn)`): the
      # first function argument, else the last argument naming a local one.
      private def wrapped_fn(call : Node, line : Int32, depth : Int32) : Fn?
        args = Noir::TreeSitter.field(call, "arguments") || return empty_fn(line)
        if inner = first_function_in(args, 0)
          return fn_from(inner, line, false)
        end
        names = [] of String
        Noir::TreeSitter.each_named_arg(args) do |arg|
          arg = Noir::TreeSitter.unwrap_expression(arg)
          names << text(arg) if type(arg) == "identifier"
        end
        names.reverse_each do |name|
          if fn = local_fn(name, depth + 1)
            return fn.direct ? fn.copy_with(direct: false) : fn
          end
        end
        Fn.new("", unparen(text(args)), line, line, false, false, EMPTY_CALLEES)
      end

      private def first_function_in(args : Node, depth : Int32) : Node?
        return if depth > MAX_RESOLVE
        Noir::TreeSitter.each_named_arg(args) do |arg|
          arg = Noir::TreeSitter.unwrap_expression(arg)
          return arg if FUNCTION_TYPES.includes?(type(arg))
          if type(arg) == "call_expression" && (inner_args = Noir::TreeSitter.field(arg, "arguments"))
            if found = first_function_in(inner_args, depth + 1)
              return found
            end
          end
        end
      end

      private def local_fn(name : String, depth : Int32) : Fn?
        return if depth > MAX_RESOLVE
        @table.locals[name]? || begin
          if decl = @decl_values[name]?
            value_fn(decl[0], decl[1], depth)
          end
        end
      end

      private def empty_fn(line : Int32) : Fn
        Fn.new("", "", line, line, false, false, EMPTY_CALLEES)
      end

      private def fn_from(node : Node, line : Int32, direct : Bool) : Fn
        params_node = Noir::TreeSitter.field(node, "parameters")
        params = if params_node
                   unparen(text(params_node))
                 elsif single = Noir::TreeSitter.field(node, "parameter")
                   text(single)
                 else
                   ""
                 end
        body_node = Noir::TreeSitter.field(node, "body")
        entries = @callees && body_node ? JSCalleeExtractor.callees_for_handler_node(node, @source, @path) : EMPTY_CALLEES
        return Fn.new(params, "", line, line, false, direct, entries) unless body_node

        body_line = Noir::TreeSitter.node_start_row(body_node) + 1
        body = type(body_node) == "statement_block" ? braced_contents(body_node) : text(body_node)
        methods = body.includes?("ethod") ? inferred_methods(body_node) : EMPTY_METHODS
        Fn.new(params, body, line, body_line, type(body_node) == "statement_block", direct, entries, methods)
      end

      # The `config` property of a default-exported object (Netlify's
      # "Fetchable module": `export default { fetch, config: {...} }`).
      private def record_config_property(node : Node) : Nil
        return unless type(node) == "object"
        Noir::TreeSitter.each_named_child(node) do |member|
          next unless type(member) == "pair"
          key = Noir::TreeSitter.field(member, "key")
          value = Noir::TreeSitter.field(member, "value")
          next unless key && value && text(key).strip("'\"") == "config"
          value = Noir::TreeSitter.unwrap_expression(value)
          @table.config ||= config_values(value) if type(value) == "object"
        end
      end

      private def default_export?(statement : Node) : Bool
        start = LibTreeSitter.ts_node_start_byte(statement).to_i
        (@source.byte_slice?(start, 40) || "").matches?(/\Aexport\s+default\b/)
      end

      # String values by key of a config object literal.
      private def config_values(object : Node) : Hash(String, Array(String))
        values = {} of String => Array(String)
        Noir::TreeSitter.each_named_child(object) do |member|
          next unless type(member) == "pair"
          key = Noir::TreeSitter.field(member, "key") || next
          value = Noir::TreeSitter.field(member, "value").try { |node| Noir::TreeSitter.unwrap_expression(node) }
          strings = [] of String
          if value
            if type(value) == "array"
              Noir::TreeSitter.each_named_arg(value) { |element| string_value(element).try { |str| strings << str } }
            else
              string_value(value).try { |str| strings << str }
            end
          end
          values[text(key).strip("'\"")] ||= strings
        end
        values
      end

      private def string_value(node : Node) : String?
        node = Noir::TreeSitter.unwrap_expression(node)
        case type(node)
        when "string"
          Noir::TreeSitter.decode_string_literal(node, @source)
        when "template_string"
          raw = text(node)
          raw.includes?("${") ? nil : raw[1...-1]
        end
      end

      # Methods a handler body checks on the request: `req.method === "POST"`
      # (also `!==`, or the literal on the left), `["GET", "HEAD"].includes(
      # req.method)` and `switch (req.method) { case "PUT": }`. The request
      # side is `x.method` / `x.httpMethod`, or a local bound from one
      # (`const { method } = req`, `const method = req.method`). Reported in
      # that order: comparisons, includes, switch cases.
      private def inferred_methods(body : Node) : Array(String)
        aliases = Set(String).new
        Noir::TreeSitter.walk(body) do |node|
          next unless type(node) == "variable_declarator"
          name = Noir::TreeSitter.field(node, "name")
          value = Noir::TreeSitter.field(node, "value").try { |v| Noir::TreeSitter.unwrap_expression(v) }
          next unless name && value
          if type(name) == "identifier" && method_member?(value)
            aliases << text(name)
          elsif type(name) == "object_pattern" && type(value) == "identifier"
            Noir::TreeSitter.each_named_child(name) do |entry|
              case type(entry)
              when "shorthand_property_identifier_pattern"
                aliases << text(entry) if METHOD_PROPERTIES.includes?(text(entry))
              when "pair_pattern"
                key = Noir::TreeSitter.field(entry, "key")
                local = Noir::TreeSitter.field(entry, "value")
                aliases << text(local) if key && local && type(local) == "identifier" && METHOD_PROPERTIES.includes?(text(key))
              end
            end
          end
        end

        compares = [] of String
        includes = [] of String
        switches = [] of String
        Noir::TreeSitter.walk(body) do |node|
          case type(node)
          when "binary_expression"
            op = Noir::TreeSitter.field(node, "operator").try { |o| text(o) }
            next unless {"==", "===", "!=", "!=="}.includes?(op)
            left = Noir::TreeSitter.field(node, "left").try { |n| Noir::TreeSitter.unwrap_expression(n) }
            right = Noir::TreeSitter.field(node, "right").try { |n| Noir::TreeSitter.unwrap_expression(n) }
            next unless left && right
            if method_ref?(left, aliases) && type(right) == "string"
              compares << string_value(right).to_s
            elsif method_ref?(right, aliases) && type(left) == "string"
              compares << string_value(left).to_s
            end
          when "call_expression"
            function = Noir::TreeSitter.field(node, "function") || next
            next unless type(function) == "member_expression"
            property = Noir::TreeSitter.field(function, "property")
            object = Noir::TreeSitter.field(function, "object").try { |n| Noir::TreeSitter.unwrap_expression(n) }
            args = Noir::TreeSitter.field(node, "arguments")
            next unless property && text(property) == "includes" && object && args && type(object) == "array"
            arg = Noir::TreeSitter.first_named_arg(args).try { |n| Noir::TreeSitter.unwrap_expression(n) }
            next unless arg && method_ref?(arg, aliases)
            Noir::TreeSitter.each_named_arg(object) { |element| includes << string_value(element).to_s if type(element) == "string" }
          when "switch_statement"
            value = Noir::TreeSitter.field(node, "value").try { |n| Noir::TreeSitter.unwrap_expression(n) }
            next unless value && method_ref?(value, aliases)
            Noir::TreeSitter.walk(node) do |inner|
              next unless type(inner) == "switch_case"
              label = Noir::TreeSitter.field(inner, "value").try { |n| Noir::TreeSitter.unwrap_expression(n) }
              switches << string_value(label).to_s if label && type(label) == "string"
            end
          end
        end

        (compares + includes + switches).map(&.upcase).select { |verb| KNOWN_METHODS.includes?(verb) }.uniq!
      end

      # `x.method` on any receiver (`ctx.request.method`, `this.req.method`,
      # `req?.method`).
      private def method_member?(node : Node) : Bool
        node = Noir::TreeSitter.unwrap_expression(node)
        return false unless type(node) == "member_expression"
        property = Noir::TreeSitter.field(node, "property")
        !!(property && METHOD_PROPERTIES.includes?(text(property)))
      end

      private def method_ref?(node : Node, aliases : Set(String)) : Bool
        method_member?(node) || (type(Noir::TreeSitter.unwrap_expression(node)) == "identifier" && aliases.includes?(text(node)))
      end

      # Text between a block's or object's braces.
      private def braced_contents(node : Node) : String
        full = text(node)
        full.size >= 2 ? full[1...-1] : ""
      end

      private def unparen(text : String) : String
        text.starts_with?('(') && text.ends_with?(')') ? text[1...-1] : text
      end

      private def type(node : Node) : String
        Noir::TreeSitter.node_type(node)
      end

      private def text(node : Node) : String
        Noir::TreeSitter.node_text(node, @source)
      end
    end
  end
end
