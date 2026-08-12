# Part of Noir::TreeSitterKotlinRouteExtractor: shared annotation/string/expression decoding helpers.
module Noir
  module TreeSitterKotlinRouteExtractor
    private def visible_kotlin_code(source : String) : String
      slash = '/'.ord.to_u8
      star = '*'.ord.to_u8
      double_quote = '"'.ord.to_u8
      single_quote = '\''.ord.to_u8
      backslash = '\\'.ord.to_u8
      newline = '\n'.ord.to_u8
      space = ' '.ord.to_u8

      bytes = source.to_slice
      mode = :code
      quote = 0_u8
      raw_string = false
      escaped = false
      i = 0

      String.build(source.bytesize) do |io|
        while i < bytes.size
          byte = bytes[i]

          case mode
          when :line_comment
            if byte == newline
              io.write_byte(byte)
              mode = :code
            else
              io.write_byte(space)
            end
            i += 1
          when :block_comment
            if byte == newline
              io.write_byte(byte)
              i += 1
            elsif i + 1 < bytes.size && byte == star && bytes[i + 1] == slash
              io.write_byte(space)
              io.write_byte(space)
              i += 2
              mode = :code
            else
              io.write_byte(space)
              i += 1
            end
          when :string
            if raw_string && i + 2 < bytes.size && byte == double_quote && bytes[i + 1] == double_quote && bytes[i + 2] == double_quote
              io.write_byte(space)
              io.write_byte(space)
              io.write_byte(space)
              i += 3
              mode = :code
              raw_string = false
            elsif !raw_string && byte == quote && !escaped
              io.write_byte(space)
              i += 1
              mode = :code
            else
              io.write_byte(byte == newline ? byte : space)
              if raw_string
                i += 1
              elsif escaped
                escaped = false
                i += 1
              else
                escaped = byte == backslash
                i += 1
              end
            end
          else
            if i + 1 < bytes.size && byte == slash && bytes[i + 1] == slash
              io.write_byte(space)
              io.write_byte(space)
              i += 2
              mode = :line_comment
            elsif i + 1 < bytes.size && byte == slash && bytes[i + 1] == star
              io.write_byte(space)
              io.write_byte(space)
              i += 2
              mode = :block_comment
            elsif i + 2 < bytes.size && byte == double_quote && bytes[i + 1] == double_quote && bytes[i + 2] == double_quote
              io.write_byte(space)
              io.write_byte(space)
              io.write_byte(space)
              i += 3
              mode = :string
              raw_string = true
            elsif byte == double_quote || byte == single_quote
              io.write_byte(space)
              quote = byte
              raw_string = false
              escaped = false
              i += 1
              mode = :string
            else
              io.write_byte(byte)
              i += 1
            end
          end
        end
      end
    end

    private def function_name(func : LibTreeSitter::TSNode, source : String) : String
      count = LibTreeSitter.ts_node_named_child_count(func)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(func, i.to_u32)
        if Noir::TreeSitter.node_type(child) == "simple_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      ""
    end

    # Walk every annotation on a class/function declaration. Kotlin
    # wraps annotations in a `modifiers` child, and each `annotation`
    # node has either a `user_type` (for `@Foo`) or a
    # `constructor_invocation` (for `@Foo("x")`/`@Foo(a = b)`).
    # Yields `(simple_name, args_node_or_nil, line)`.
    private def each_annotation(decl : LibTreeSitter::TSNode, source : String, &)
      mods = find_modifiers(decl)
      return unless mods
      Noir::TreeSitter.each_named_child(mods) do |ann|
        next unless Noir::TreeSitter.node_type(ann) == "annotation"
        Noir::TreeSitter.each_named_child(ann) do |child|
          case Noir::TreeSitter.node_type(child)
          when "user_type"
            name = simple_annotation_name(Noir::TreeSitter.node_text(child, source))
            yield name, nil, Noir::TreeSitter.node_start_row(ann)
          when "constructor_invocation"
            # `user_type` + `value_arguments` pair.
            inner_name = ""
            args : LibTreeSitter::TSNode? = nil
            Noir::TreeSitter.each_named_child(child) do |sub|
              case Noir::TreeSitter.node_type(sub)
              when "user_type"
                inner_name = simple_annotation_name(Noir::TreeSitter.node_text(sub, source))
              when "value_arguments"
                args = sub
              end
            end
            yield inner_name, args, Noir::TreeSitter.node_start_row(ann) unless inner_name.empty?
          end
        end
      end
    end

    private def find_modifiers(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "modifiers"
      end
      nil
    end

    private def simple_annotation_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    # Kotlin `value_arguments` contains `value_argument` children.
    # Each argument is either positional (a single child that's a
    # literal) or named (has a `simple_identifier` + expression).
    private def annotation_paths(args_node : LibTreeSitter::TSNode?,
                                 source : String,
                                 string_constants : Hash(String, String),
                                 local_string_constants : Hash(String, String)) : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      positional = [] of String
      keyword = [] of String

      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless value_node

        if kind == :keyword
          next unless key == "value" || key == "path"
          collect_string_values(value_node, source, keyword, string_constants, local_string_constants)
        elsif kind == :bare_identifier
          if value = local_string_constants[key]?
            positional << value unless value.empty?
          end
        else
          collect_string_values(value_node, source, positional, string_constants, local_string_constants)
        end
      end

      keyword.empty? ? positional : keyword
    end

    # Return `{:keyword | :positional | :bare_identifier, key_or_nil, value_node}`.
    private def classify_value_argument(arg : LibTreeSitter::TSNode, source : String) : Tuple(Symbol, String, LibTreeSitter::TSNode?)
      children = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(arg) do |child|
        children << child
      end
      if children.size <= 1
        child = children.first?
        if child && Noir::TreeSitter.node_type(child) == "simple_identifier"
          return {:bare_identifier, Noir::TreeSitter.node_text(child, source), child}
        end
        return {:positional, "", child}
      end

      key = ""
      value : LibTreeSitter::TSNode? = nil
      named = false
      children.each do |entry|
        case Noir::TreeSitter.node_type(entry)
        when "simple_identifier"
          if named
            # second identifier is actually the value expression
            value = entry
          else
            key = Noir::TreeSitter.node_text(entry, source)
            named = true
          end
        else
          value = entry if value.nil?
        end
      end
      {named ? :keyword : :positional, key, value}
    end

    # Collect path values from a node. Handles string literals,
    # constants, `PATH + "/suffix"`, collection literals, and
    # `arrayOf("/a", PATH)` call expressions.
    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      source : String,
                                      sink : Array(String),
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String))
      case Noir::TreeSitter.node_type(node)
      when "collection_literal"
        # Kotlin's `[...]` array syntax inside annotations.
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants)
        end
      when "parenthesized_expression"
        # Stray-annotation case: `@RequestMapping("/x")` gets parsed
        # as `annotation` + sibling `parenthesized_expression`
        # carrying a bare `string_literal` (no `value_arguments`
        # wrapper).
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants)
        end
      when "call_expression"
        # `arrayOf("/a", "/b")` — walk the value_arguments.
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "call_suffix"
            Noir::TreeSitter.each_named_child(child) do |suf|
              next unless Noir::TreeSitter.node_type(suf) == "value_arguments"
              Noir::TreeSitter.each_named_child(suf) do |va|
                next unless Noir::TreeSitter.node_type(va) == "value_argument"
                Noir::TreeSitter.each_named_child(va) do |v|
                  collect_string_values(v, source, sink, string_constants, local_string_constants)
                end
              end
            end
          end
        end
      else
        if value = resolve_string_value(node, source, string_constants, local_string_constants)
          sink << value unless value.empty?
        end
      end
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     string_constants : Hash(String, String),
                                     local_string_constants : Hash(String, String)) : String?
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source, string_constants, local_string_constants)
      when "simple_identifier"
        # A bare const reference. Spring controllers idiomatically keep
        # their path constants in a shared `Paths.kt` and reference them
        # unqualified (`@RequestMapping(path = [PUBLIC_URL])`), so fall
        # back to the cross-file constant map when the name isn't local.
        name = Noir::TreeSitter.node_text(node, source)
        local_string_constants[name]? || string_constants[name]?
      when "navigation_expression"
        text = Noir::TreeSitter.node_text(node, source)
        local_string_constants[text]? || fully_qualified_constant(text, string_constants)
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          return resolve_string_value(child, source, string_constants, local_string_constants)
        end
      when "additive_expression"
        parts = [] of String
        Noir::TreeSitter.each_named_child(node) do |child|
          part = resolve_string_value(child, source, string_constants, local_string_constants)
          return unless part
          parts << part
        end
        parts.join
      end
    end

    private def fully_qualified_constant(text : String, string_constants : Hash(String, String)) : String?
      return unless text.count('.') >= 2
      string_constants[text]?
    end

    private def last_navigation_segment(node : LibTreeSitter::TSNode, source : String) : String
      result = ""
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "simple_identifier"
          result = Noir::TreeSitter.node_text(child, source)
        when "navigation_suffix"
          Noir::TreeSitter.each_named_child(child) do |sub|
            if Noir::TreeSitter.node_type(sub) == "simple_identifier"
              result = Noir::TreeSitter.node_text(sub, source)
            end
          end
        end
      end
      result
    end

    # Extract verbs from `method = RequestMethod.X` / `method =
    # [RequestMethod.X, RequestMethod.Y]` / `method = arrayOf(...)`.
    private def annotation_methods(args_node : LibTreeSitter::TSNode?, source : String) : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      methods = [] of String
      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless kind == :keyword
        next unless key == "method"
        next unless value_node
        collect_request_method_values(value_node, source, methods)
      end
      methods
    end

    private def each_method_call_arguments(source : String, method_name : String, &)
      offset = 0
      name_size = method_name.size

      while marker = source.index(method_name, offset)
        offset = marker + name_size
        next unless method_call_name?(source, marker, name_size)

        open_idx = source.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(source, open_idx)
        next unless close_idx

        args = source[(open_idx + 1)...close_idx]
        line = source[0...marker].count('\n') + 1
        yield args, line
      end
    end

    private def method_call_name?(source : String, marker : Int32, name_size : Int32) : Bool
      before = marker.zero? ? '\0' : source[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = marker + name_size
      while after_idx < source.size && source[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < source.size && source[after_idx] == '('
    end

    private def top_level_arguments(args : String) : Array(String)
      result = [] of String
      start = 0
      depth = 0
      in_string = false
      escaped = false

      args.each_char.with_index do |char, index|
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          if depth.zero?
            result << args[start...index].strip
            start = index + 1
          end
        end
      end

      tail = args[start..]?.try(&.strip)
      result << tail if tail && !tail.empty?
      result
    end

    private def resolve_route_expression(expression : String,
                                         string_constants : Hash(String, String),
                                         local_string_constants : Hash(String, String),
                                         depth = 0) : String?
      return if depth > 8
      value = expression.strip
      return if value.empty?

      if value.starts_with?('"') && value.ends_with?('"')
        return value[1...-1]
      end

      if value.starts_with?("arrayOf(") && value.ends_with?(")")
        inner = value["arrayOf(".size...-1]
        values = top_level_arguments(inner).compact_map do |entry|
          resolve_route_expression(entry, string_constants, local_string_constants, depth + 1)
        end
        return values.first?
      end

      if value.includes?('+')
        parts = top_level_plus_parts(value)
        if parts.size > 1
          resolved_parts = parts.compact_map do |part|
            resolve_route_expression(part, string_constants, local_string_constants, depth + 1)
          end
          return resolved_parts.join if resolved_parts.size == parts.size
        end
      end

      if resolved = local_string_constants[value]?
        return resolved
      end
      if resolved = string_constants[value]?
        return resolved
      end

      if idx = value.rindex('.')
        short_name = value[(idx + 1)..]
        if resolved = local_string_constants[short_name]?
          return resolved
        end
        if resolved = string_constants[short_name]?
          return resolved
        end
      end

      nil
    end

    # Resolve an argument to every string value it denotes. `arrayOf(a, b)`
    # yields all elements; any other expression yields its single resolved
    # value. Used for vararg/array sinks (STOMP `addEndpoint(...)` /
    # `setApplicationDestinationPrefixes(...)`) where keeping only the first
    # entry would drop real endpoints/prefixes.
    private def resolve_route_expressions(expression : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : Array(String)
      value = expression.strip
      if value.starts_with?("arrayOf(") && value.ends_with?(")")
        inner = value["arrayOf(".size...-1]
        return top_level_arguments(inner).compact_map do |entry|
          resolve_route_expression(entry, string_constants, local_string_constants)
        end
      end

      if resolved = resolve_route_expression(value, string_constants, local_string_constants)
        [resolved]
      else
        [] of String
      end
    end

    private def top_level_plus_parts(value : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      escaped = false

      value.each_char.with_index do |char, index|
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '+'
          if depth.zero?
            parts << value[start...index].strip
            start = index + 1
          end
        end
      end

      tail = value[start..]?.try(&.strip)
      parts << tail if tail && !tail.empty?
      parts
    end

    private def find_matching_paren(source : String, open_idx : Int32) : Int32?
      depth = 0
      in_string = false
      escaped = false
      quote = '\0'

      source.each_char.with_index do |char, index|
        next if index < open_idx

        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '('
          depth += 1
        when ')'
          depth -= 1
          return index if depth.zero?
        end
      end

      nil
    end

    # `RequestMethod.GET` is parsed as `navigation_expression` with a
    # `navigation_suffix` carrying the verb. Array forms recurse.
    private def collect_request_method_values(node : LibTreeSitter::TSNode, source : String, sink : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "navigation_expression"
        # Walk to the final `navigation_suffix` child for the verb name.
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "navigation_suffix"
          Noir::TreeSitter.each_named_child(child) do |id|
            sink << Noir::TreeSitter.node_text(id, source).upcase if Noir::TreeSitter.node_type(id) == "simple_identifier"
          end
        end
      when "simple_identifier"
        sink << Noir::TreeSitter.node_text(node, source).upcase
      when "collection_literal"
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_request_method_values(elem, source, sink)
        end
      when "call_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "call_suffix"
          Noir::TreeSitter.each_named_child(child) do |suf|
            next unless Noir::TreeSitter.node_type(suf) == "value_arguments"
            Noir::TreeSitter.each_named_child(suf) do |va|
              next unless Noir::TreeSitter.node_type(va) == "value_argument"
              Noir::TreeSitter.each_named_child(va) do |v|
                collect_request_method_values(v, source, sink)
              end
            end
          end
        end
      end
    end

    # Kotlin `string_literal` wraps content in `string_content`
    # children, same shape as Java. A `$VAR` / `${VAR}` interpolation
    # that names a known compile-time constant (e.g.
    # `@GetMapping("$PUBLIC_URL/version")`) resolves to the constant's
    # value; anything else (a real runtime template) is preserved as a
    # `{VAR}` placeholder. Literal `{id}` path params live in
    # `string_content`, so they're never affected by this resolution.
    private def decode_string_literal(node : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String)? = nil,
                                      local_constants : Hash(String, String)? = nil) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          when "interpolated_identifier", "interpolated_expression"
            ident = Noir::TreeSitter.node_text(child, source).strip
            resolved = (local_constants.try &.[ident]?) || (constants.try &.[ident]?)
            if resolved
              io << resolved
            else
              io << '{' << ident << '}'
            end
          end
        end
      end
      buf
    end
  end
end
