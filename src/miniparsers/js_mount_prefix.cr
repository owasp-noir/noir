require "set"
require "./js_ts_ast_helpers"
require "../models/endpoint"
require "../utils/url_path"

module Noir
  # Internal prefix carrier; stripped before an Express endpoint leaves analysis.
  module JSMountPrefix
    extend self
    include JSTSAstHelpers

    UNREAD  = '\u{FDD0}'
    DEFAULT = '\u{FDD1}'

    def marked?(path : String) : Bool
      path.includes?(UNREAD) || path.includes?(DEFAULT)
    end

    def visible(path : String) : String
      marked?(path) ? path.delete("#{UNREAD}#{DEFAULT}") : path
    end

    def join(parent : String, child : String) : String
      marker = if parent.includes?(UNREAD) || child.includes?(UNREAD)
                 UNREAD
               elsif parent.includes?(DEFAULT) || child.includes?(DEFAULT)
                 DEFAULT
               else
                 return URLPath.join(parent, child)
               end
      "#{marker}#{URLPath.join(visible(parent), visible(child))}"
    end

    def finish(endpoint : Endpoint) : Endpoint
      if marked?(endpoint.url)
        unresolved = endpoint.url.includes?(UNREAD) || endpoint.resolution.try(&.["prefix"]?) == Endpoint::RESOLUTION_UNRESOLVED
        endpoint.url = visible(endpoint.url)
        endpoint.url = "/" if endpoint.url.empty?
        endpoint.mark_resolution("prefix", unresolved ? Endpoint::RESOLUTION_UNRESOLVED : Endpoint::RESOLUTION_HEURISTIC)
      end
      endpoint
    end

    ENV_PROPERTY = /\Aprocess\.env(?:\.[\w$]+|\[(['"])[^'"]+\1\])\z/

    private def env_default(node, source) : String?
      return unless TreeSitter.node_type(node) == "binary_expression"
      op = TreeSitter.field(node, "operator") || return
      return unless TreeSitter.node_text(op, source).in?("||", "??")
      lhs = TreeSitter.field(node, "left") || return
      return unless TreeSitter.node_text(lhs, source).matches?(ENV_PROPERTY)
      rhs = TreeSitter.field(node, "right") || return
      return unless TreeSitter.node_type(rhs) == "string"
      decode_string(rhs, source) + DEFAULT
    end

    # Keep provenance on values until all mounts and template substitutions
    # have been composed. Only declarations depending on the environment are
    # added to the ordinary table of string constants.
    def environment_constants(source : String, path : String, constants : Hash(String, String)) : Nil
      # Boolean guards, equality checks and finished property reads cannot
      # seed a default. A bare object, subscript, comment or unfamiliar
      # expression still goes through the AST, as do imported defaults.
      unless constants.any? { |_, value| value.includes?(DEFAULT) }
        return unless source.includes?("process.env") && (source.includes?("||") || source.includes?("??") || source.matches?(/}\s*=\s*process\.env/))
        return unless source.matches?(/process\.env(?!\s*&&|\.[\w$]+\s*(?:[,;)\]}]|[!=]==?|&&))/)
      end
      TreeSitter.parse_js_family(source, path) do |root|
        TreeSitter.walk(root) do |node|
          next unless TreeSitter.node_type(node) == "variable_declarator"
          name = TreeSitter.field(node, "name") || next
          value = TreeSitter.field(node, "value") || next
          key = TreeSitter.node_text(name, source)
          value = TreeSitter.unwrap_expression(value)
          if TreeSitter.node_type(value) == "call_expression" && TreeSitter.field(value, "function").try { |fn| TreeSitter.node_text(fn, source) } == "Object.freeze"
            value = arguments_node(value).try { |args| TreeSitter.first_named_arg(args) } || next
          end
          if TreeSitter.node_type(name) == "object_pattern" && TreeSitter.node_text(value, source) == "process.env"
            TreeSitter.each_named_child(name) do |item|
              item = TreeSitter.field(item, "value") || item
              left = TreeSitter.field(item, "left") || next
              right = TreeSitter.field(item, "right") || next
              next unless TreeSitter.node_type(right) == "string"
              constants[TreeSitter.node_text(left, source)] = decode_string(right, source) + DEFAULT
            end
          elsif TreeSitter.node_type(name) == "identifier"
            if TreeSitter.node_type(value) == "object"
              TreeSitter.each_named_child(value) do |prop|
                member = TreeSitter.field(prop, "key") || prop
                expr = TreeSitter.field(prop, "value") || prop
                default = env_default(expr, source) || constants[TreeSitter.node_text(expr, source)]?
                constants["#{key}.#{TreeSitter.node_text(member, source)}"] = default if default && default.includes?(DEFAULT)
              end
            elsif default = env_default(value, source) || constants[TreeSitter.node_text(value, source)]?
              constants[key] = default if default.includes?(DEFAULT)
            end
          end
        end
      end
    end

    # A function reference in the first slot is middleware, not a path.
    def middleware?(expression : String, context : String) : Bool
      return true if expression.matches?(/\A\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[\w$]+\s*=>)/)
      return false unless expression.strip.matches?(/\A[A-Za-z_$][\w$]*\z/)
      name = Regex.escape(expression.strip)
      context.matches?(/\bfunction\s+#{name}\s*\(|\b#{name}\s*=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[\w$]+\s*=>)/)
    end

    # ponytail: helper mount keys are file-wide; omit shadowed names until bindings are keyed by declaration scope.
    def unique_bindings(content : String, path : String, names : Array(String)) : Set(String)
      counts = names.to_h { |name| {name, 0} }
      patterns = names.map { |name| {name, /(?<![\w$])#{Regex.escape(name)}(?![\w$])/} }
      TreeSitter.parse_js_family(content, path) do |root|
        TreeSitter.walk(root) do |node|
          pattern = case TreeSitter.node_type(node)
                    when "variable_declarator", "function_declaration", "function_expression", "class_declaration"
                      TreeSitter.field(node, "name")
                    when "assignment_expression", "augmented_assignment_expression", "for_in_statement"
                      TreeSitter.field(node, "left")
                    when "update_expression"
                      TreeSitter.field(node, "argument")
                    when "arrow_function", "catch_clause"
                      TreeSitter.field(node, "parameter")
                    when "formal_parameters", "import_clause"
                      node
                    end
          next unless pattern
          text = TreeSitter.node_text(pattern, content)
          patterns.each do |name, name_pattern|
            counts[name] += 1 if text.matches?(name_pattern)
          end
        end
      end
      counts.select { |_, count| count == 1 }.keys.to_set
    end

    # Read only a final rooted tail, never a literal on either side of a gap.
    def read(expression : String, constants : Hash(String, String), context : String = "", legacy_prefix : String? = nil,
             *, legacy_constants : Hash(String, String)? = nil) : String
      result = UNREAD.to_s
      # A bare constant keeps the scanner's existing read. New expressions
      # must not trust a legacy seed taken from only the first literal.
      if legacy_constants && legacy_constants.has_key?(expression.strip)
        return constants[expression.strip]? || legacy_constants[expression.strip]
      end
      source = "(#{expression})"
      TreeSitter.parse_js_family(source, "prefix.js") do |root|
        next if TreeSitter.node_has_error?(root)
        statement = TreeSitter.first_named_child(root)
        node = statement.try { |s| TreeSitter.first_named_child(s) }
        next unless node
        blocked = false
        if legacy = legacy_constants
          TreeSitter.walk(node) do |part|
            next unless TreeSitter.node_type(part).in?("identifier", "member_expression")
            name = TreeSitter.node_text(part, source)
            blocked = true if legacy.has_key?(name) && !constants.has_key?(name)
          end
        end
        next if blocked
        result = value(node, source, constants, context, true, 0) || UNREAD.to_s
      end
      # ponytail: preserve previously emitted partial prefixes; replace them with tails when URL replacement is allowed.
      return "#{UNREAD}#{legacy_prefix}" if legacy_prefix && result.includes?(UNREAD)
      result
    end

    private def value(node : LibTreeSitter::TSNode, source : String, constants : Hash(String, String),
                      context : String, partial : Bool, depth : Int32) : String?
      return if depth > TreeSitter::MAX_AST_DEPTH
      node = TreeSitter.unwrap_expression(node)
      case TreeSitter.node_type(node)
      when "string"
        decode_string(node, source)
      when "identifier", "member_expression"
        constants[TreeSitter.node_text(node, source)]?
      when "binary_expression"
        if default = env_default(node, source)
          return default
        end
        operator = TreeSitter.field(node, "operator")
        return unless operator && TreeSitter.node_text(operator, source) == "+"
        left = TreeSitter.field(node, "left")
        right = TreeSitter.field(node, "right")
        return unless left && right
        a = value(left, source, constants, context, partial, depth + 1)
        b = value(right, source, constants, context, false, depth + 1)
        if a && b
          "#{a}#{b}"
        elsif partial && b && b.starts_with?('/') && unread_operand?(left, source, constants, context, depth + 1)
          "#{UNREAD}#{b}"
        end
      when "template_string"
        parts = [] of String
        unread = false
        TreeSitter.each_named_child(node) do |child|
          case TreeSitter.node_type(child)
          when "string_fragment", "escape_sequence"
            text = TreeSitter.node_text(child, source)
            parts << (TreeSitter.node_type(child) == "escape_sequence" ? TreeSitter.unescape(text) : text)
          when "template_substitution"
            expr = TreeSitter.first_named_child(child)
            resolved = expr.try { |e| value(e, source, constants, context, false, depth + 1) }
            if resolved
              parts << resolved
            elsif partial && parts.empty? && expr && unread_operand?(expr, source, constants, context, depth + 1)
              unread = true
            else
              return
            end
          else
            return
          end
        end
        text = parts.join
        return text unless unread
        "#{UNREAD}#{text}" if text.starts_with?('/')
      end
    end

    private def unread_operand?(node : LibTreeSitter::TSNode, source : String, constants : Hash(String, String),
                                context : String, depth : Int32) : Bool
      return false if depth > TreeSitter::MAX_AST_DEPTH
      node = TreeSitter.unwrap_expression(node)
      case TreeSitter.node_type(node)
      when "identifier"
        name = TreeSitter.node_text(node, source)
        # ponytail: reject locally built names conservatively; follow their definitions before keeping a tail.
        !constants.has_key?(name) && !context.matches?(/\b#{Regex.escape(name)}\s*=\s*[^;\n]*['"`]/)
      when "member_expression", "subscript_expression", "call_expression"
        value(node, source, constants, context, false, depth + 1).nil?
      when "binary_expression"
        op = TreeSitter.field(node, "operator")
        left = TreeSitter.field(node, "left")
        right = TreeSitter.field(node, "right")
        !!(op && TreeSitter.node_text(op, source) == "+" && left && right &&
          unread_operand?(left, source, constants, context, depth + 1) && unread_operand?(right, source, constants, context, depth + 1))
      else
        false
      end
    end
  end
end
