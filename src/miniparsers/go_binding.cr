require "./go_struct_fields"
require "../models/endpoint"

# A destination keeps the file where its type was written, including when a
# helper accepts it as an interface or a generic parameter.
module Noir::GoBinding
  extend self
  alias TS = Noir::TreeSitter
  record Destination, type : String, file : String, local_types : Hash(String, String)? = nil
  alias Arguments = Hash(String, Destination)

  record Local, type : String, value : LibTreeSitter::TSNode?, declaration : LibTreeSitter::TSNode, parameter : Bool = false do
    def expression(source) : String
      value.try { |node| TS.node_text(node, source) } || ""
    end
  end

  private def assignment(type, node, key) : Local
    expr = TS.field(node, key).try { |list| TS.first_named_arg(list) }
    Local.new(type, expr, node)
  end

  # Look backwards through enclosing Go blocks. A later declaration or a
  # variable declared in a sibling closure cannot type this call's argument.
  def local(name : String, at : LibTreeSitter::TSNode, source : String) : Local?
    child = at
    while parent = TS.parent(child)
      case TS.node_type(parent)
      when "statement_list", "block"
        latest = nil
        TS.each_named_child(parent) do |statement|
          break if LibTreeSitter.ts_node_start_byte(statement) >= LibTreeSitter.ts_node_start_byte(child)
          if TS.node_type(statement) == "var_declaration"
            TS.walk(statement) do |spec|
              next unless TS.node_type(spec) == "var_spec" && node_field(spec, "name", source) == name
              latest = assignment(node_field(spec, "type", source), spec, "value")
            end
          elsif {"short_var_declaration", "assignment_statement"}.includes?(TS.node_type(statement))
            names = node_field(statement, "left", source).split(',').map(&.strip)
            if names.first? == name
              declared = latest.try(&.type) || ""
              latest = assignment(declared, statement, "right")
            end
          end
        end
        return latest if latest
      when "function_declaration", "method_declaration", "func_literal"
        {"parameters", "receiver", "result"}.each do |key|
          next unless list = TS.field(parent, key)
          TS.each_named_child(list) do |param|
            next unless TS.node_type(param) == "parameter_declaration"
            TS.each_named_child(param) do |id|
              return Local.new(node_field(param, "type", source), nil, param, parameter: true) if TS.node_type(id) == "identifier" && TS.node_text(id, source) == name
            end
          end
        end
      end
      child = parent
    end
    nil
  end

  def node_field(node, key, source) : String
    TS.field(node, key).try { |field| TS.node_text(field, source) } || ""
  end

  IDENT        = /\A[\p{L}_][\p{L}\d_]*\z/
  TYPE_LITERAL = /\A(?:&\s*)?((?:\w+\.)?\w+)\s*\{/
  NEW_TYPE     = /\Anew\(\s*((?:\w+\.)?\w+)\s*\)\z/

  # Local type declarations share the scope of their block. Keep this
  # environment with the destination when it crosses into a helper's file.
  private def typed(type, file, at, source) : Destination
    return Destination.new(type, file) unless source.includes?("type")
    locals = Hash(String, String).new
    child = at
    while parent = TS.parent(child)
      if {"statement_list", "block"}.includes?(TS.node_type(parent))
        TS.each_named_child(parent) do |statement|
          break if LibTreeSitter.ts_node_start_byte(statement) >= LibTreeSitter.ts_node_start_byte(child)
          next unless TS.node_type(statement) == "type_declaration"
          TS.each_named_child(statement) do |spec|
            next unless {"type_spec", "type_alias"}.includes?(TS.node_type(spec))
            locals.put_if_absent(node_field(spec, "name", source)) { node_field(spec, "type", source) }
          end
        end
      end
      child = parent
    end
    Destination.new(type, file, locals.empty? ? nil : locals)
  end

  def destination(text, call, source, file, forwarded : Arguments, depth = 0) : Destination?
    return if depth > 8
    name = text.strip.lchop('&').strip
    expr = name
    if name.matches?(IDENT)
      decl = local(name, call, source)
      return forwarded[name]? unless decl
      if decl.value.nil?
        return forwarded[name] if decl.parameter && forwarded.has_key?(name)
        return typed(decl.type, file, decl.declaration, source)
      end
      return typed(decl.type, file, decl.declaration, source) unless decl.type.empty?
      if type = literal_type(decl.value, source)
        return typed(type, file, decl.declaration, source)
      end
      expr = decl.expression(source)
      if value = decl.value
        if expr.lchop('&').matches?(IDENT)
          return destination(expr, value, source, file, forwarded, depth + 1)
        end
      end
    elsif text.includes?('{') && (args = TS.field(call, "arguments"))
      TS.each_named_arg(args) do |arg|
        next unless TS.node_text(arg, source) == text
        if type = literal_type(arg, source)
          return typed(type, file, arg, source)
        end
      end
    end
    if factory = forwarded[expr]?
      return factory
    end
    if m = expr.match(TYPE_LITERAL) || expr.match(NEW_TYPE)
      typed(m[1], file, call, source)
    end
  end

  private def literal_type(value, source) : String?
    value = TS.field(value, "operand") if value && TS.node_type(value) == "unary_expression"
    node_field(value, "type", source) if value && TS.node_type(value) == "composite_literal"
  end

  # A method value can close over a different request factory at each
  # registration. Read the literal on that receiver's reaching assignment.
  alias FactorySites = Hash(Tuple(Int32, String), Arguments)

  def factory_sites(source : String, file : String) : FactorySites
    sites = FactorySites.new
    TS.parse_go(source) do |root|
      TS.walk(root) do |call|
        next unless TS.node_type(call) == "call_expression" && (args = TS.field(call, "arguments"))
        TS.each_named_arg(args) do |arg|
          next unless TS.node_type(arg) == "selector_expression"
          receiver = node_field(arg, "operand", source)
          next unless receiver.matches?(IDENT)
          value = local(receiver, call, source).try(&.value) || next
          value = TS.field(value, "operand") if TS.node_type(value) == "unary_expression"
          next unless value && TS.node_type(value) == "composite_literal" && (body = TS.field(value, "body"))
          factories = Arguments.new
          TS.each_named_child(body) do |entry|
            next unless TS.node_type(entry) == "keyed_element"
            key = node_field(entry, "key", source)
            field = TS.field(entry, "value").try { |v| TS.first_named_arg(v) }
            next unless field && TS.node_type(field) == "func_literal"
            block = TS.field(field, "body") || next
            # Only a factory with a single unconditional composite-literal return.
            if match = TS.node_text(block, source).match(/\A\{\s*return\s+&?((?:\w+\.)?\w+)\s*\{[^{}]*\}\s*;?\s*\}\z/m)
              factories[key] = Destination.new(match[1], file)
            end
          end
          unless factories.empty?
            sites[{TS.node_start_row(call), TS.node_text(arg, source)}] = factories
          end
        end
      end
    end
    sites
  end

  # JSON keeps a named nested object as one key, like the JVM DTO reader.
  # An anonymous field is promoted only when this binder gives it no name.
  def names(index, dest : Destination, key : String, fallback : Bool, gin_default = false,
            visiting = Set(Destination).new) : Array(String)?
    return if visiting.includes?(dest)
    visiting << dest
    if local_type = dest.local_types.try(&.[dest.type.lchop('*')]?)
      result = names(index, Destination.new(local_type, dest.file, dest.local_types), key, fallback, gin_default, visiting)
      visiting.delete(dest)
      return result
    end
    file, fields = index.declaration(dest.type, dest.file) || return
    local_types = dest.local_types if dest.type.matches?(/\Astruct\s*\{/)
    result = [] of String
    fields.each do |field|
      exported = field.name.split('.').last[0]?.try(&.uppercase?)
      next unless field.embedded || exported
      tags = field.tag.scan(/(?:\A|\s)(\w+):"([^"]*)"/).to_h { |m| {m[1], m[2].split(',').first} }
      wire = tags[key]?
      next if wire == "-"
      if field.embedded && wire.to_s.empty?
        nested = names(index, Destination.new(field.type, file, local_types), key, fallback, gin_default, visiting)
        if nested
          result.concat(nested)
          next
        end
      end
      next unless exported
      if wire.to_s.empty?
        next unless fallback
        next if gin_default && tags.has_key?("form") && !tags.has_key?("json")
        wire = field.name.split('.').last
      end
      result << wire if wire && !wire.empty?
    end
    visiting.delete(dest)
    result
  end

  def opaque(type : String) : Param
    param = Param.new("body", "", type)
    param.tags << Tag.new("unresolved", "Request binding destination could not be expanded", "go")
    param
  end

  # Each entry is the wire tag, output location and whether an exported
  # untagged field binds by Go name.
  def params(kind : String, method : String, dest : Destination?, index : Noir::GoStructFields::Index?) : Array(Param)
    rules = case kind
            when "echo"
              tags = [{"param", "path", false}]
              tags << {"query", "query", false} if {"GET", "HEAD", "DELETE"}.includes?(method)
              tags.concat([{"json", "json", true}, {"form", "form", false}]) unless {"GET", "HEAD"}.includes?(method)
              tags
            when "gin"
              method == "GET" ? [{"form", "query", true}] : [{"json", "json", true}, {"form", "form", true}]
            when "query"       then [{"form", "query", true}]
            when "echo_query"  then [{"query", "query", false}]
            when "uri"         then [{"uri", "path", true}]
            when "param"       then [{"param", "path", false}]
            when "header"      then [{"header", "header", true}]
            when "echo_header" then [{"header", "header", false}]
            when "form"        then [{"form", "form", true}]
            when "json"        then [{"json", "json", true}]
            else                    return [opaque("json")]
            end
    result = [] of Param
    resolved = false
    if dest && index
      rules.each do |key, location, fallback|
        if fields = names(index, dest, key, fallback, gin_default: kind == "gin" && key == "json")
          resolved = true
          fields.each { |name| result << Param.new(name, "", location) }
        end
      end
    end
    resolved ? result : [opaque({"echo", "gin"}.includes?(kind) ? "json" : rules.first[1])]
  end
end
