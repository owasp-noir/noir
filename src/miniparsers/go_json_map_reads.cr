require "./go_binding"

module Noir::GoRequestParamExtractor
  # Track the first result of helpers that decode JSON objects or batches of
  # objects. A literal key on some other map in the handler is not an input.
  # Keep the opaque binding as well: other keys may be computed at runtime.
  private class JSONMapReads
    alias TS = Noir::TreeSitter
    alias Env = Hash(String, Symbol)
    getter names = Set(String).new
    @returns = false
    @reachable_calls : Set(UInt32)?

    def initialize(@resolver : Resolver, @file : String, @method : String, @depth = 0)
    end

    def analyze(body, source, env : Env, strings = Hash(String, String).new) : Bool
      if source.includes?(".Method")
        calls = Set(UInt32).new
        requests = env.select { |_, value| value == :request }.keys.to_set
        GoRequestParamExtractor.reachable_nodes(body, source, @method, requests) do |node|
          calls << LibTreeSitter.ts_node_start_byte(node) if TS.node_type(node) == "call_expression"
        end
        @reachable_calls = calls
      end
      visit(body, source, env, strings)
      @returns
    end

    private def visit(node, source, env, strings) : Symbol
      case TS.node_type(node)
      when "identifier"
        return env.fetch(TS.node_text(node, source), :unknown)
      when "assignment_statement", "short_var_declaration"
        if right = TS.field(node, "right").try { |list| TS.first_named_arg(list) }
          value = visit(right, source, env, strings)
          name = GoBinding.node_field(node, "left", source).split(',').first.strip
          env[name] = value if name.matches?(GoBinding::IDENT)
        end
      when "return_statement"
        if expr = TS.first_named_arg(node).try { |list| TS.first_named_arg(list) }
          @returns = true if visit(expr, source, env, strings) == :json
        end
      when "range_clause"
        if (right = TS.field(node, "right")) && visit(right, source, env, strings) == :json
          names = GoBinding.node_field(node, "left", source).split(',')
          env[names.last.strip] = :json if names.size == 2
        end
      when "type_switch_statement"
        scoped = env.dup
        name = GoBinding.node_field(node, "alias", source)
        scoped[name] = :json if env[GoBinding.node_field(node, "value", source)]? == :json
        TS.each_named_arg(node) { |child| visit(child, source, scoped, strings) }
      when "type_assertion_expression"
        operand = TS.field(node, "operand") || return :unknown
        return visit(operand, source, env, strings)
      when "index_expression"
        if env[GoBinding.node_field(node, "operand", source)]? == :json
          raw = GoBinding.node_field(node, "index", source)
          key = literal(raw) || strings[raw]?
          @names << key if key
        end
      when "call_expression"
        return visit_call(node, source, env, strings)
      when "literal_element", "literal_value", "composite_literal"
        TS.each_named_arg(node) { |child| return :json if visit(child, source, env, strings) == :json }
      when "func_literal"
        # A closure is a separate flow.
      else
        scoped = {"block", "for_statement", "type_case"}.includes?(TS.node_type(node)) ? env.dup : env
        TS.each_named_arg(node) { |child| visit(child, source, scoped, strings) }
      end
      :unknown
    end

    private def literal(text)
      text.match(/\A["`]([^"`\\]*)["`]\z/).try(&.[1])
    end

    private def visit_call(node, source, env, strings) : Symbol
      return :unknown if @reachable_calls.try { |calls| !calls.includes?(LibTreeSitter.ts_node_start_byte(node)) }
      list = TS.field(node, "arguments") || return :unknown
      name = GoBinding.node_field(node, "function", source)
      args = [] of String
      values = [] of Symbol
      TS.each_named_arg(list) do |arg|
        args << TS.node_text(arg, source)
        values << visit(arg, source, env, strings)
      end
      if name.ends_with?(".Decode") || name.ends_with?(".Unmarshal")
        requests = env.select { |_, value| value == :request }.keys.to_set
        ctx = Context.new(@resolver, @file, [] of String, strings, requests)
        target = GoRequestParamExtractor.binding_target(node, source, ctx)
        if target.is_a?(Tuple) && target[0] == "json"
          env[target[1].lchop('&')] = :json
        end
        return :unknown
      end
      return :json if name == "append" && values.includes?(:json)
      return :unknown if @depth >= MAX_HELPER_DEPTH || !values.any?(&.in?(:json, :request))
      fn = if name.matches?(GoBinding::IDENT)
             @resolver.bodies.functions_for(File.dirname(@file))[name]?
           else
             @resolver.method_value(name, node, source, @file, GoBinding::Arguments.new)
           end
      return :unknown unless fn
      signature = fn.source.match(HELPER_PARAMS) || return :unknown
      return :unknown unless values.includes?(:json) || fn.source.lines.first.includes?("map[")
      bound = Env.new
      literals = Hash(String, String).new
      signature[1].split(',').each_with_index do |param, i|
        key = param.strip.split(/\s+/).first
        bound[key] = values[i]? || :unknown
        if (arg = args[i]?) && (value = literal(arg) || strings[arg]?)
          literals[key] = value
        end
      end
      child = JSONMapReads.new(@resolver, fn.file_path, @method, @depth + 1)
      result = false
      @resolver.with_binding_tree(fn.source, fn.file_path) do |root, text|
        decl = TS.node_type(root) == "source_file" ? TS.first_named_child(root) : root
        if decl && TS.node_type(decl) == "package_clause"
          TS.each_named_arg(root) { |n| decl = n if TS.field(n, "body") }
        end
        if decl && (body = TS.field(decl, "body"))
          result = child.analyze(body, text, bound, literals)
        end
      end
      @names.concat(child.names)
      result ? :json : :unknown
    end
  end
end
