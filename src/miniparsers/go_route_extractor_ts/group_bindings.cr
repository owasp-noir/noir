module Noir::TreeSitterGoRouteExtractor
  ENV_BINDINGS = "\0env"

  alias GroupAST = Noir::TreeSitter
  alias FieldPrefixes = Hash({String, String, String}, Set(String))

  # Keep the fallback on the os.Getenv binding that the empty test checks.
  # Another function can use the same variable name for an exact literal.
  private def collect_environment_defaults(root, source, values)
    GroupAST.walk(root) do |node|
      next unless GroupAST.node_type(node) == "if_statement"
      cond = GroupAST.field(node, "condition") || next
      test = GroupAST.node_text(cond, source).match(/\A(\w+)\s*(==|!=)\s*""\z/) || next
      name = test[1]
      binding = GroupAST.field(node, "initializer") || GoBinding.local(name, node, source).try(&.declaration)
      next unless binding && GoBinding.node_field(binding, "left", source) == name
      next unless GoBinding.node_field(binding, "right", source).starts_with?("os.Getenv(")
      block = GroupAST.field(node, "consequence") || next
      branch = block_statements(block)
      next unless branch.size == 1
      first = branch.first
      rhs = if test[2] == "==" && GoBinding.node_field(first, "left", source) == name
              GroupAST.field(first, "right").try { |list| GroupAST.first_named_arg(list) }
            end
      if rhs && (fallback = environment_literal(rhs, source))
        values[ENV_BINDINGS] = ""
        values["env:#{name}"] = ""
        values["env:#{node_key(binding)}"] = fallback
        values["after:#{node_key(binding)}"] = LibTreeSitter.ts_node_end_byte(node).to_s
      end

      function = enclosing_function(node) || next
      next unless GroupAST.node_type(function) == "function_declaration" &&
                  GoBinding.node_field(function, "result", source) == "string"
      fn_body = GroupAST.field(function, "body") || next
      statements = block_statements(fn_body)
      # Only the getenv binding, the empty check and the final return.
      statements.shift if statements.first?.try(&.id) == binding.id
      next unless statements.size == 2 && statements.first.id == node.id
      final = returned_expression(statements.last) || next
      early = returned_expression(first)
      default = if test[2] == "==" && GroupAST.node_text(final, source) == name
                  rhs || early
                elsif test[2] == "!=" && early && GroupAST.node_text(early, source) == name
                  final
                end
      next unless default
      fn = GoBinding.node_field(function, "name", source)
      if fallback = environment_literal(default, source)
        values["env:#{fn}()"] = "#{fallback}#{HEURISTIC_PREFIX}"
      elsif index = default_parameter_index(function, default, source)
        values["env-arg:#{fn}()"] = index.to_s
      else
        next
      end
      values[ENV_BINDINGS] = ""
    end
  end

  private def default_parameter_index(function, default, source) : Int32?
    return unless GroupAST.node_type(default) == "identifier"
    name = GroupAST.node_text(default, source)
    params = GroupAST.field(function, "parameters") || return
    index = 0
    GroupAST.each_named_arg(params) do |param|
      type = GroupAST.field(param, "type") || return
      GroupAST.each_named_arg(param) do |id|
        next if id.id == type.id
        return index if GroupAST.node_text(id, source) == name && GroupAST.node_text(type, source) == "string"
        index += 1
      end
    end
    nil
  end

  private def block_statements(block)
    nodes = [] of LibTreeSitter::TSNode
    list = GroupAST.first_named_arg(block)
    body = list && GroupAST.node_type(list) == "statement_list" ? list : block
    GroupAST.each_named_arg(body) { |node| nodes << node }
    nodes
  end

  private def returned_expression(statement)
    return unless GroupAST.node_type(statement) == "return_statement"
    GroupAST.first_named_arg(statement).try { |list| GroupAST.first_named_arg(list) }
  end

  private def environment_literal(node, source)
    decode_string_literal(node, source) if GroupAST.node_type(node).in?("interpreted_string_literal", "raw_string_literal")
  end

  private def environment_binding(node, name, source, values) : String?
    local = GoBinding.local(name, node, source) || return
    key = node_key(local.declaration)
    if fallback = values["env:#{key}"]?
      after = values["after:#{key}"].to_u32
      return LibTreeSitter.ts_node_start_byte(node) >= after ? "#{fallback}#{HEURISTIC_PREFIX}" : UNREAD_PREFIX.to_s
    end
    if value = local.value
      return UNREAD_PREFIX.to_s if local.expression(source).starts_with?("os.Getenv(")
      environment_literal(value, source)
    end
  end

  # Bind keyed router fields to the group parameter of the function
  # constructing the struct. The type, field and package identify the
  # binding even when the method uses a different receiver name.
  def builder_field_prefixes(source, types, builders, prefixes, unknown, found : FieldPrefixes)
    GroupAST.parse_go(source) do |root|
      scopes = builder_param_groups(root, source, builders)
      strings = nil
      GroupAST.walk(root) do |call|
        next unless GroupAST.node_type(call) == "call_expression"
        selector = GroupAST.field(call, "function") || next
        owner = GroupAST.field(selector, "operand") || next
        next unless GroupAST.node_type(owner) == "identifier"
        local = GoBinding.local(GroupAST.node_text(owner, source), call, source) || next
        value = local.value
        value = GroupAST.field(value, "operand") if value && GroupAST.node_type(value) == "unary_expression"
        literal = value if value && GroupAST.node_type(value) == "composite_literal"
        type = literal ? GoBinding.node_field(literal, "type", source) : local.type.lchop('*')
        fields = types[type]? || next
        method = GoBinding.node_field(selector, "field", source)
        row = GroupAST.node_start_row(local.declaration)
        scope = scopes.find { |(first, last, _)| first <= row <= last }
        builder = scope && builders.find { |_, rb| rb.start_row == scope[0] }
        body = literal.try { |lit| GroupAST.field(lit, "body") }
        fields.each do |field|
          placements = found.put_if_absent({type, method, field}) { Set(String).new }
          arg = body.try { |init| wrapper_field_value(init, source, field) }
          unless builder && scope && arg
            placements << UNREAD_PREFIX.to_s
            next
          end
          strings ||= collect_string_values(root, source)
          groups = scope[2]
          binding = builder_arg_text(arg, source, groups, strings)
          relative = binding && (groups[binding]? || binding)
          unless relative && relative.includes?(HANDED_PREFIX)
            placements << UNREAD_PREFIX.to_s
            next
          end
          tail = relative.delete(HANDED_PREFIX)
          bases = prefixes.try(&.[builder[0]]?)
          bases.try &.each { |base| placements << group_join(base, tail) }
          placements << group_join(UNREAD_PREFIX.to_s, tail) if !bases || unknown.try(&.includes?(builder[0]))
        end
      end
    end
  end

  private def wrapper_field_value(body, source, field)
    GroupAST.each_named_arg(body) do |element|
      next unless GroupAST.node_type(element) == "keyed_element" && GoBinding.node_field(element, "key", source) == field
      return GroupAST.field(element, "value").try { |value| GroupAST.first_named_arg(value) }
    end
    nil
  end

  def place_field_routes(source, routes : Array(Route), fields : FieldPrefixes)
    return routes if fields.empty? || routes.none?(&.router_name.includes?('.'))
    placed = Hash(Int32, Array(Route)).new
    GroupAST.parse_go(source) do |root|
      GroupAST.each_named_arg(root) do |decl|
        next unless GroupAST.node_type(decl) == "method_declaration"
        receiver = GroupAST.field(decl, "receiver").try { |params| GroupAST.first_named_arg(params) } || next
        type = GoBinding.node_field(receiver, "type", source).lchop('*')
        name = GoBinding.node_field(receiver, "name", source)
        method = GoBinding.node_field(decl, "name", source)
        rows = GroupAST.node_start_row(decl)..GroupAST.node_end_row(decl)
        routes.each_with_index do |route, i|
          next unless rows.includes?(route.line)
          owner, _, field = route.router_name.partition('.')
          next unless owner == name && (placements = fields[{type, method, field}]?)
          placed[i] = placements.map { |prefix| route.under_field_prefix(prefix) }
        end
      end
    end
    routes.map_with_index { |route, i| placed[i]? || [route] }.flatten
  end
end
