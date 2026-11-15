require "set"
require "./js_ts_ast_helpers"
require "../models/endpoint"
require "../utils/url_path"

module Noir
  # Internal prefix carrier; stripped before an Express endpoint leaves analysis.
  module JSMountPrefix
    extend self
    include JSTSAstHelpers

    UNREAD = '\u{FDD0}'

    def join(parent : String, child : String) : String
      return URLPath.join(parent, child) unless parent.includes?(UNREAD) || child.includes?(UNREAD)
      "#{UNREAD}#{URLPath.join(parent.delete(UNREAD), child.delete(UNREAD))}"
    end

    def finish(endpoint : Endpoint) : Endpoint
      if endpoint.url.includes?(UNREAD)
        endpoint.url = endpoint.url.delete(UNREAD)
        endpoint.url = "/" if endpoint.url.empty?
        endpoint.resolution = (endpoint.resolution || {} of String => String).merge({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
      end
      endpoint
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
          names.each do |name|
            counts[name] += 1 if text.matches?(/(?<![\w$])#{Regex.escape(name)}(?![\w$])/)
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
      return legacy_constants[expression.strip] if legacy_constants && legacy_constants.has_key?(expression.strip)
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
