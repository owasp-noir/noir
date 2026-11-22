require "./js_handler_resolver"

module Noir
  # Follow the actual arguments at a route registration. A Body value describes
  # the top-level fields still supplied by the client after copies and writes.
  class JSBodyFlow
    alias TS = TreeSitter
    alias Node = LibTreeSitter::TSNode
    MAX_DEPTH = 3

    record Value, kind : Symbol, excluded = Set(String).new, keys = [] of String, uncertain = false, open_keys = false
    alias Args = Array(Value?)
    record Definition, path : String, source : String
    record Installed, path : String, line : Int32
    alias Index = Hash(Int32, Array(Tuple(String, String)))

    @indexes = {} of String => Index
    @modules = {} of String => Hash(String, Installed)
    @targets = {} of {String, String} => Definition?
    @steps = {} of {String, String, String} => Array(Param)
    @sources = {} of String => String

    def initialize(&@read : String -> String)
    end

    private def source(path)
      @sources[path] ||= @read.call(path)
    end

    def apply(endpoint : Endpoint) : Nil
      endpoint.details.code_paths.each do |location|
        location.route_middleware.try &.each do |step|
          next unless step.origin.in?(:route, :helper)
          source = step.source.strip
          fields_for(step.file, source, endpoint.method).each { |p| endpoint.push_param(p) }
        end
      end
    end

    private def fields_for(path : String, step : String, method : String) : Array(Param)
      key = {path, step, method}
      @steps[key] ||= begin
        result = Endpoint.new("", method)
        analyze_step(path, step, method, result)
        result.params
      end
    end

    private def analyze_step(path, step, method, result)
      if step.starts_with?('[') && step.ends_with?(']')
        TopLevelSplit.split(step[1...-1], ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |part|
          fields_for(path, part.strip, method).each { |param| result.push_param(param) }
        end
        return
      end
      args = Args.new
      if bound = step.match(/\A([\w$.]+)\.bind\(\s*(?:null|undefined)\s*,\s*(\[[^\]]*\])\s*\)\z/)
        keys = bound[2].scan(/['"]([^'"]+)['"]/).map(&.[1])
        args << Value.new(:keys, keys: keys)
        step = bound[1]
      end
      args << Value.new(:request)
      defn = if step.matches?(JSRouteExtractor::INLINE_CLOSURE_START_RE)
               Definition.new(path, step)
             else
               target(path, step)
             end
      return unless defn
      visit(defn, args, result, MAX_DEPTH, Set({Definition, Args}).new)
    rescue
      # A failed parse of one optional step must preserve the endpoint and
      # the independently recovered fields from its other handlers.
      nil
    end

    def visit(fn : Definition, args : Args, result : Endpoint, depth : Int32, seen : Set({Definition, Args})) : Nil
      # A stack entry includes the argument positions: a second call with a
      # different object in slot two can legitimately read different fields.
      return unless candidate?(fn, args)
      key = {fn, args.map { |v| v.try { |a| a.copy_with(excluded: a.excluded.dup) } }}
      return unless seen.add?(key)
      begin
        Frame.new(self, fn, result, depth, seen).run(args)
      ensure
        seen.delete(key)
      end
    end

    @request_candidates = {} of Definition => Bool

    # Most middleware uses only req.uid, req.params, etc. A request can
    # carry body fields here only if the function reads body/files or uses
    # the whole value (including as an argument or a destructuring source).
    private def candidate?(fn, args)
      return true unless args.size == 1 && args.first.try(&.kind) == :request
      @request_candidates.fetch(fn) do
        text = fn.source
        start = text.match(/\A(?:async\s*)?\(\s*([\w$]+)\s*(?:,[^(){}]*)?\)\s*=>/) || return true
        name = Regex.escape(start[1])
        @request_candidates[fn] = !!text.match(/(?<![\w$.])#{name}\b(?!\s*\??\.\s*(?!body\b|files\b)[\w$])/, start.end(0))
      end
    end

    def target(path : String, name : String) : Definition?
      key = {path, name}
      return @targets[key] if @targets.has_key?(key)
      @targets[key] = resolve(path, name)
    end

    private def resolve(path, name)
      content = source(path)
      handler = JSHandlerResolver.resolve(name, content, path, true)
      if handler && (file = handler.path) && (line = handler.line)
        if entries = index(file)[line]?
          short = handler.name.split('.').last
          entry = entries.find { |item| item[0] == short }
          entry ||= entries.find(&.[0].empty?) unless name.matches?(/\A[\w$]+\.[\w$]+\z/)
          entry ||= entries.first if entries.size == 1 && !name.includes?('.')
          return Definition.new(file, entry[1]) if entry
        end
      end
      # CommonJS mixins install methods on the object passed to require().
      parts = name.split('.')
      return unless parts.size == 2
      file = if imported = JSHandlerResolver.imports_of(content, path)[parts[0]]?
               JSHandlerResolver.resolve_specifier(path, imported[0])
             elsif parts[0].matches?(/\A(?:#{JSHandlerResolver.export_aliases(content)})\z/)
               path
             end
      return unless file
      method = installed(file)[parts[1]]? || return
      entry = index(method.path)[method.line]?.try(&.find { |item| item[0] == parts[1] })
      Definition.new(method.path, entry[1]) if entry
    end

    private def installed(path)
      @modules[path] ||= begin
        methods = {} of String => Installed
        code = source(path)
        aliases = JSHandlerResolver.export_aliases(code)
        code.scan(/^\s*require\(['"]([^'"]+)['"]\)\((#{aliases})\)/m) do |registration|
          file = JSHandlerResolver.resolve_specifier(path, registration[1]) || next
          child = source(file)
          factory = child.match(/module\.exports\s*=\s*(?:function\s*)?\(\s*([\w$]+)\s*\)/) || next
          child.scan(/^\s*#{Regex.escape(factory[1])}\.([\w$]+)\s*=/m) do |assignment|
            line = child.byte_slice(0, assignment.byte_begin(1)).count('\n') + 1
            methods[assignment[1]] = Installed.new(file, line)
          end
        end
        methods
      end
    end

    private def index(file : String) : Index
      @indexes[file] ||= begin
        functions = Index.new
        content = source(file)
        TS.parse_js_family(content, file) do |root|
          each_definition(root) do |node|
            owner = TS.parent(node) || next
            if TS.node_type(owner) == "arguments"
              call = TS.parent(owner)
              owner = TS.parent(call) || owner if call
            end
            identifier = TS.field(node, "name") || TS.field(owner, "left") || TS.field(owner, "key") || TS.field(owner, "name")
            name = identifier.try { |n| TS.node_text(n, content).split('.').last.strip("'\"") } || ""
            params = TS.field(node, "parameters") || TS.field(node, "parameter") || next
            body = TS.field(node, "body") || next
            text = "#{TS.node_text(params, content)} => #{TS.node_text(body, content)}"
            entry = {name, text}
            line = TS.node_start_row(node) + 1
            (functions[line] ||= [] of Tuple(String, String)) << entry
            other = TS.node_start_row(owner) + 1
            (functions[other] ||= [] of Tuple(String, String)) << entry if other != line && TS.node_type(owner).in?("assignment_expression", "pair", "variable_declarator")
          end
        end
        functions
      end
    end

    private def each_definition(node : Node, &block : Node ->) : Nil
      case TS.node_type(node)
      when "program", "statement_block", "export_statement", "expression_statement", "lexical_declaration", "variable_declaration",
           "variable_declarator", "assignment_expression", "object", "pair", "parenthesized_expression", "call_expression", "arguments",
           "class_declaration", "class_body", "public_field_definition", "return_statement"
        TS.each_named_child(node) { |child| each_definition(child, &block) }
      when "arrow_function", "function_expression", "function_declaration", "method_definition", "generator_function_declaration", "generator_function"
        yield node
        TS.field(node, "body").try { |body| each_definition(body, &block) }
      end
    end

    private class Frame
      @env = {} of String => Value?
      @source : String
      @records = {} of String => Hash(String, Value)

      def initialize(@flow : JSBodyFlow, @fn : Definition, @result : Endpoint, @depth : Int32, @seen : Set({Definition, Args}))
        @source = "(#{@fn.source})"
      end

      def run(args)
        TS.parse_js_family(@source, @fn.path) do |root|
          statement = TS.first_named_child(root) || next
          expression = TS.first_named_child(statement) || next
          function = TS.unwrap_expression(expression)
          execute(function, args)
        end
      end

      private def execute(function, args)
        params = TS.field(function, "parameters") || TS.field(function, "parameter") || return
        if TS.node_type(params) == "formal_parameters"
          children(params).each_with_index { |p, i| bind(p, args[i]?) }
        else
          bind(params, args.first?)
        end
        TS.field(function, "body").try { |body| eval_node(body) }
      end

      private def children(node)
        list = [] of Node
        TS.each_named_child(node) { |child| list << child unless TS.node_type(child) == "comment" }
        list
      end

      private def text(node)
        TS.node_text(node, @source)
      end

      private def bind(pattern, value) : Nil
        case TS.node_type(pattern)
        when "identifier", "shorthand_property_identifier_pattern"
          @env[text(pattern)] = value
        when "object_pattern"
          children(pattern).each do |item|
            prop = TS.field(item, "key") || TS.field(item, "left") || item
            var = TS.field(item, "value") || prop
            next unless key = literal_key(prop)
            bind(var, member(value, key))
          end
        when "assignment_pattern", "required_parameter", "optional_parameter"
          inner = TS.field(pattern, "pattern") || TS.field(pattern, "left")
          bind(inner, value) if inner
        end
      end

      private def literal_key(node)
        case TS.node_type(node)
        when "string"                                                                                                      then text(node)[1...-1]
        when "identifier", "property_identifier", "shorthand_property_identifier", "shorthand_property_identifier_pattern" then text(node)
        end
      end

      private def member(value, key, uncertain = false) : Value?
        return unless value
        return if value.excluded.includes?(key)
        if value.kind == :request
          return Value.new(:body) if key == "body"
          return Value.new(:files) if key == "files"
        elsif value.kind.in?(:body, :files) && key != "length"
          param = Param.new(key, "", value.kind == :files ? "file" : "json")
          param.add_tag(Tag.new("unresolved", "Possible body field from a conditional value or computed key", "analyzer")) if uncertain || value.uncertain
          @result.push_param(param)
        end
        nil
      end

      private def eval_node(node : Node) : Value?
        case TS.node_type(node)
        when "identifier", "shorthand_property_identifier"
          return @env[text(node)]?
        when "member_expression", "subscript_expression"
          return read_member(node)
        when "if_statement"
          branch(node)
          return
        when "variable_declarator", "assignment_expression"
          left = TS.field(node, "name") || TS.field(node, "left") || return
          right = TS.field(node, "value") || TS.field(node, "right") || return
          value = eval_node(right)
          # A transformation can return its input (e.g. an extensible filter).
          # Retain that possibility only for the same binding or named slot.
          @records.delete(text(left))
          if value.nil? && TS.node_type(left) == "object_pattern"
            slots = passed_slots(right)
            bind(left, nil)
            children(left).each do |pattern|
              key = TS.field(pattern, "key") || pattern
              bind(TS.field(pattern, "value") || key, slots[text(key)]?)
            end
            return
          end
          value ||= transformed(left, right)
          if TS.node_type(left).in?("member_expression", "subscript_expression")
            exclude(left)
          else
            bind(left, value)
          end
          return value
        when "object"
          return object_value(node)
        when "array"
          entries = children(node)
          keys = entries.select { |n| TS.node_type(n) == "string" }.compact_map { |n| literal_key(n) }
          entries.each { |entry| eval_node(entry) }
          return Value.new(:keys, keys: keys, open_keys: keys.size < entries.size) unless keys.empty?
          return
        when "call_expression"
          return call(node)
        when "ternary_expression"
          return conditional(node)
        when "binary_expression"
          left = TS.field(node, "left") || return
          right = TS.field(node, "right") || return
          a = eval_node(left)
          b = eval_node(right)
          op = TS.field(node, "operator").try { |n| text(n) }
          return a || b if op.in?("||", "??")
          return
        when "parenthesized_expression", "as_expression", "await_expression", "spread_element"
          return TS.first_named_child(node).try { |inner| eval_node(inner) }
        when "unary_expression"
          if text(node).starts_with?("delete ")
            TS.field(node, "argument").try { |arg| exclude(arg) }
            return
          end
        when "statement_block"
          scoped_block(node)
          return
        when "function_declaration", "function_expression", "arrow_function", "class_declaration"
          return
        end
        TS.each_named_child(node) { |child| eval_node(child) }
        nil
      end

      # Restore lexical declarations when leaving a nested block. Assignments
      # to outer variables and writes through object aliases stay visible.
      private def scoped_block(node)
        saved = {} of String => Value?
        TS.each_named_child(node) do |stmt|
          if TS.node_type(stmt) == "lexical_declaration"
            children(stmt).each do |decl|
              var = TS.field(decl, "name") || next
              saved[text(var)] = @env[text(var)]?
            end
          end
          eval_node(stmt)
        end
        saved.each { |name, value| @env[name] = value }
      end

      private def branch(node)
        TS.field(node, "condition").try { |cond| eval_node(cond) }
        outer = @env
        branches = {"consequence", "alternative"}.map do |side|
          copies = {} of UInt64 => Set(String)
          @env = outer.transform_values do |value|
            value.try do |v|
              excluded = copies[v.excluded.object_id] ||= v.excluded.dup
              v.copy_with(excluded: excluded)
            end
          end
          TS.field(node, side).try { |child| eval_node(child) }
          @env
        end
        @env = outer
        (branches[0].keys | branches[1].keys).each do |name|
          a, b = branches.map(&.[name]?)
          unless value = a || b
            @env[name] = nil
            next
          end
          if a && b && a.kind == b.kind
            excluded = a.excluded & b.excluded
            if (prior = outer[name]?) && prior.kind == value.kind
              prior.excluded.concat(excluded)
              excluded = prior.excluded
            end
            @env[name] = value.copy_with(excluded: excluded, uncertain: a.uncertain || b.uncertain)
          else
            @env[name] = value.copy_with(uncertain: true)
          end
        end
      end

      private def transformed(left, right) : Value?
        node = TS.unwrap_expression(right)
        node = TS.first_named_child(node) || return if TS.node_type(node) == "await_expression"
        name = text(left)
        if TS.node_type(node) == "member_expression"
          obj = TS.field(node, "object") || return
          key = TS.field(node, "property") || return
          return @records[text(obj)]?.try(&.[name]?) if text(key) == name
        end
        return unless TS.node_type(node) == "call_expression"
        args = TS.field(node, "arguments") || return
        if children(args).any? { |arg| TS.node_type(arg) == "identifier" && name == text(arg) }
          return @env[name]?.try(&.copy_with(uncertain: true))
        end
        slots = passed_slots(node)
        @records[name] = slots unless slots.empty?
        nil
      end

      # Preserve a possible body only under the key actually passed to the
      # transform. A similarly named property in another object is independent.
      private def passed_slots(expression)
        slots = {} of String => Value
        node = TS.unwrap_expression(expression)
        node = TS.first_named_child(node) || return slots if TS.node_type(node) == "await_expression"
        return slots unless TS.node_type(node) == "call_expression"
        args = TS.field(node, "arguments") || return slots
        children(args).each do |arg|
          next unless TS.node_type(arg) == "object"
          children(arg).each do |entry|
            key = TS.field(entry, "key") || entry
            var = TS.field(entry, "value") || entry
            @env[text(var)]?.try { |v| slots[text(key)] = v.copy_with(uncertain: true) }
          end
        end
        slots
      end

      private def exclude(node)
        obj = TS.field(node, "object") || return
        prop = TS.field(node, "property") || TS.field(node, "index") || return
        value = eval_node(obj)
        if TS.node_type(node) == "subscript_expression" && TS.node_type(prop) != "string"
          eval_node(prop)
        elsif key = literal_key(prop)
          value.try(&.excluded.add(key))
        end
      end

      private def read_member(node)
        obj = TS.field(node, "object") || return
        value = eval_node(obj)
        if prop = TS.field(node, "property")
          return member(value, text(prop))
        end
        idx = TS.field(node, "index") || return
        eval_node(idx)
        if TS.node_type(idx) == "string"
          return member(value, text(idx)[1...-1])
        elsif TS.node_type(idx) == "identifier"
          keys = @env[text(idx)]?
          if keys && keys.kind == :keys
            keys.keys.each { |key| member(value, key) }
            member(value, text(idx), uncertain: true) if keys.open_keys
          else
            member(value, text(idx), uncertain: true)
          end
        end
        nil
      end

      private def object_value(node)
        value = nil
        TS.each_named_child(node) do |entry|
          if TS.node_type(entry) == "spread_element"
            spread = eval_node(entry)
            value = spread.copy_with(excluded: spread.excluded.dup) if spread && spread.kind == :body
          else
            TS.field(entry, "value").try { |v| eval_node(v) }
            key = TS.field(entry, "key") || entry
            literal_key(key).try { |k| value.try(&.excluded.add(k)) }
          end
        end
        value
      end

      private def conditional(node)
        condition = TS.field(node, "condition") || return
        eval_node(condition)
        yes = TS.field(node, "consequence") || return
        no = TS.field(node, "alternative") || return
        if m = text(condition).match(/\A([\w$]+)\.method\s*([!=]==?)\s*['"]([A-Z]+)['"]\z/)
          if @env[m[1]]?.try(&.kind) == :request
            matches = (@result.method == m[3]) == m[2].starts_with?('=')
            return eval_node(matches ? yes : no)
          end
        end
        a = eval_node(yes)
        b = eval_node(no)
        (a || b).try(&.copy_with(uncertain: true))
      end

      private def call(node)
        fn = TS.field(node, "function") || return
        args = TS.field(node, "arguments") || return
        nodes = children(args)
        values = nodes.map { |arg| eval_node(arg) }
        receiver = TS.field(fn, "object").try { |obj| eval_node(obj) }
        name = text(fn)
        if name == "Object.assign" && (base = values.first?) && base.kind == :body
          nodes.skip(1).each do |arg|
            children(arg).each { |entry| TS.field(entry, "key").try { |k| base.excluded << text(k) } } if TS.node_type(arg) == "object"
          end
          return base
        end
        prop = TS.field(fn, "property").try { |p| text(p) }
        if name == "Object.hasOwn" && (base = values.first?) && (key = nodes[1]?) && TS.node_type(key) == "string"
          member(base, text(key)[1...-1])
        end
        if prop == "hasOwnProperty" && receiver && (arg = nodes.first?)
          if TS.node_type(arg) == "string"
            member(receiver, text(arg)[1...-1])
          elsif (keys = values.first?) && keys.kind == :keys
            keys.keys.each { |field| member(receiver, field) }
          end
        end
        nodes.each do |callback|
          next unless JSHandlerTable::FUNCTION_TYPES.includes?(TS.node_type(callback))
          # A callback can capture a body alias but its own arguments shadow it.
          outer = @env
          @env = outer.dup
          execute(callback, [receiver.try { |v| v if v.kind == :keys && prop.in?("map", "filter", "forEach") }] of Value?)
          @env = outer
        end
        return receiver if receiver && receiver.kind == :keys && prop.in?("filter", "concat", "slice")
        return values.first? if name.ends_with?(".uniq") && values.first?.try(&.kind) == :keys
        if @depth > 0 && values.any? { |v| v && v.kind.in?(:request, :body, :files) } && name.matches?(/\A[\w$]+(?:\.[\w$]+)*\z/)
          if target = @flow.target(@fn.path, name)
            @flow.visit(target, values, @result, @depth - 1, @seen)
          end
        end
        nil
      end
    end
  end
end
