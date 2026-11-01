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
      block : Bool, direct : Bool, callees : Array(JSCalleeExtractor::Entry)

    class Table
      getter exports = {} of String => Fn
      getter locals = {} of String => Fn
      # Members of an exported object literal (`export const handler = { GET() {} }`,
      # also `define.handlers({...})`), by export name. A member that is not a
      # function (`GET: 5`) is nil: the key is still there.
      getter objects = {} of String => Hash(String, Fn?)
      property default : Fn?
      property config : String?
    end

    EMPTY_CALLEES  = [] of JSCalleeExtractor::Entry
    MAX_RESOLVE    = 4
    FUNCTION_TYPES = Set{"function_declaration", "generator_function_declaration", "function_expression", "generator_function", "arrow_function"}

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
        Reader.new(source, path, callees, table).read(root)
      end
      table
    rescue
      Table.new
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
                @table.config ||= braced_contents(value)
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
        if type(body_node) == "statement_block"
          Fn.new(params, braced_contents(body_node), line, body_line, true, direct, entries)
        else
          Fn.new(params, text(body_node), line, body_line, false, direct, entries)
        end
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
          @table.config ||= braced_contents(value) if type(value) == "object"
        end
      end

      private def default_export?(statement : Node) : Bool
        start = LibTreeSitter.ts_node_start_byte(statement).to_i
        (@source.byte_slice?(start, 40) || "").matches?(/\Aexport\s+default\b/)
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
