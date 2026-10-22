# Part of Noir::TreeSitterKotlinRouteExtractor: GraphQL @SchemaMapping/@QueryMapping routes and arguments.
module Noir
  module TreeSitterKotlinRouteExtractor
    struct GraphqlRoute
      getter operation_keyword : String
      getter root_kind : String
      getter field_name : String
      getter line : Int32
      getter class_name : String
      getter method_name : String
      getter arguments : Array(NamedTuple(name: String, type: String))

      def initialize(@operation_keyword, @root_kind, @field_name, @line, @class_name, @method_name, @arguments)
      end
    end

    def extract_graphql_routes_from(root : LibTreeSitter::TSNode,
                                    source : String,
                                    string_constants = Hash(String, String).new,
                                    local_string_constants : Hash(String, String)? = nil) : Array(GraphqlRoute)
      routes = [] of GraphqlRoute
      file_constants = local_string_constants || extract_string_constants(source)
      walk_graphql_mapping_routes(root, source, string_constants, file_constants, routes)
      routes
    end

    # ---- private helpers ----------------------------------------------

    private def walk_graphql_mapping_routes(node : LibTreeSitter::TSNode,
                                            source : String,
                                            string_constants : Hash(String, String),
                                            local_string_constants : Hash(String, String),
                                            routes : Array(GraphqlRoute),
                                            depth = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "class_declaration" || Noir::TreeSitter.node_type(node) == "object_declaration"
        class_name = type_identifier_text(node, source)
        if body = class_body(node)
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "function_declaration"
              collect_graphql_function_routes(member, source, class_name, string_constants, local_string_constants, routes)
            when "class_declaration", "object_declaration"
              walk_graphql_mapping_routes(member, source, string_constants, local_string_constants, routes, depth + 1)
            end
          end
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_graphql_mapping_routes(child, source, string_constants, local_string_constants, routes, depth + 1)
      end
    end

    private def collect_graphql_function_routes(func : LibTreeSitter::TSNode,
                                                source : String,
                                                class_name : String,
                                                string_constants : Hash(String, String),
                                                local_string_constants : Hash(String, String),
                                                routes : Array(GraphqlRoute))
      method_name = function_name(func, source)
      return if method_name.empty?

      each_annotation(func, source) do |ann_name, args, ann_line|
        operation =
          case ann_name
          when "QueryMapping"
            {"query", "Query"}
          when "MutationMapping"
            {"mutation", "Mutation"}
          when "SubscriptionMapping"
            {"subscription", "Subscription"}
          when "SchemaMapping"
            type_names = schema_mapping_type_names(args, source, string_constants, local_string_constants)
            type_names = [graphql_schema_source_type(func, source)] if type_names.empty?
            type_names = type_names.reject(&.empty?)
            next if type_names.empty?

            field_names = schema_mapping_field_names(args, source, string_constants, local_string_constants)
            field_names = [method_name] if field_names.empty?

            field_names.each do |field_name|
              field = field_name.lstrip('/').strip
              next if field.empty?
              type_names.each do |type_name|
                routes << GraphqlRoute.new(
                  "field", type_name, field, ann_line, class_name, method_name,
                  graphql_arguments(func, source, string_constants, local_string_constants)
                )
              end
            end
            next
          end
        next unless operation

        operation_keyword, root_kind = operation
        names = annotation_paths(args, source, string_constants, local_string_constants)
        names = [method_name] if names.empty?

        names.each do |name|
          field_name = name.lstrip('/').strip
          next if field_name.empty?
          routes << GraphqlRoute.new(
            operation_keyword, root_kind, field_name, ann_line, class_name, method_name,
            graphql_arguments(func, source, string_constants, local_string_constants)
          )
        end
      end
    end

    private def schema_mapping_field_names(args : LibTreeSitter::TSNode?,
                                           source : String,
                                           string_constants : Hash(String, String),
                                           local_string_constants : Hash(String, String)) : Array(String)
      graphql_annotation_string_values(args, source, ["value", "field"], string_constants, local_string_constants)
    end

    private def schema_mapping_type_names(args : LibTreeSitter::TSNode?,
                                          source : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : Array(String)
      graphql_annotation_string_values(args, source, ["typeName"], string_constants, local_string_constants)
    end

    private def graphql_annotation_string_values(args_node : LibTreeSitter::TSNode?,
                                                 source : String,
                                                 allowed_keys : Array(String),
                                                 string_constants : Hash(String, String),
                                                 local_string_constants : Hash(String, String)) : Array(String)
      values = [] of String
      return values unless args_node
      return values unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      positional = [] of String
      keyword = [] of String
      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless value_node

        if kind == :keyword
          next unless allowed_keys.includes?(key)
          collect_string_values(value_node, source, keyword, string_constants, local_string_constants)
        elsif allowed_keys.includes?("value")
          collect_string_values(value_node, source, positional, string_constants, local_string_constants)
        end
      end

      keyword.empty? ? positional : keyword
    end

    private def graphql_schema_source_type(func : LibTreeSitter::TSNode, source : String) : String
      params_node = function_parameters(func)
      return "" unless params_node

      pending_modifiers : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(params_node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "parameter_modifiers"
          pending_modifiers = child
        when "parameter"
          if pending_modifiers && graphql_argument_modifier?(pending_modifiers, source)
            pending_modifiers = nil
            next
          end

          type_name = kotlin_parameter_type(child, source)
          return type_name unless type_name.empty?
          pending_modifiers = nil
        else
          pending_modifiers = nil
        end
      end

      ""
    end

    private def graphql_arguments(func : LibTreeSitter::TSNode,
                                  source : String,
                                  string_constants : Hash(String, String),
                                  local_string_constants : Hash(String, String)) : Array(NamedTuple(name: String, type: String))
      params_node = function_parameters(func)
      return [] of NamedTuple(name: String, type: String) unless params_node

      args = [] of NamedTuple(name: String, type: String)
      pending_argument : String? = nil
      count = LibTreeSitter.ts_node_named_child_count(params_node)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(params_node, i.to_u32)
        child_type = Noir::TreeSitter.node_type(child)
        case child_type
        when "parameter_modifiers"
          pending_argument = graphql_argument_override(child, source, string_constants, local_string_constants) if graphql_argument_modifier?(child, source)
        when "simple_identifier"
          next unless pending_argument
          param_name = Noir::TreeSitter.node_text(child, source)
          arg_name = pending_argument.empty? ? param_name : pending_argument
          arg_type = graphql_argument_type(params_node, source, (i + 1).to_i32)
          args << {name: arg_name, type: arg_type}
          pending_argument = nil
        when "parameter"
          next unless pending_argument
          param_name = kotlin_parameter_name(child, source)
          next if param_name.empty?
          arg_name = pending_argument.empty? ? param_name : pending_argument
          args << {name: arg_name, type: kotlin_parameter_type(child, source)}
          pending_argument = nil
        else
          pending_argument = nil if pending_argument && child_type != "annotation"
        end
      end

      args
    end

    private def function_parameters(func : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(func) do |child|
        return child if Noir::TreeSitter.node_type(child) == "function_value_parameters"
      end
      nil
    end

    private def kotlin_parameter_name(node : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(node) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "simple_identifier"
      end
      ""
    end

    private def kotlin_parameter_type(node : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "user_type", "nullable_type"
          return Noir::TreeSitter.node_text(child, source).rstrip('?')
        end
      end
      "String"
    end

    private def graphql_argument_modifier?(node : LibTreeSitter::TSNode, source : String) : Bool
      Noir::TreeSitter.node_text(node, source).includes?("@Argument")
    end

    private def graphql_argument_override(node : LibTreeSitter::TSNode,
                                          source : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : String
      text = Noir::TreeSitter.node_text(node, source)
      if match = text.match(/@Argument\s*\(\s*"([^"]+)"/)
        return match[1]
      end
      if match = text.match(/@Argument\s*\([^)]*\b(?:name|value)\s*=\s*"([^"]+)"/)
        return match[1]
      end

      annotation_argument_values(node, source).each do |key, value_node|
        next unless key.empty? || key == "name" || key == "value"
        if value = resolve_string_value(value_node, source, string_constants, local_string_constants)
          return value unless value.empty?
        end
      end

      ""
    end

    private def annotation_argument_values(node : LibTreeSitter::TSNode,
                                           source : String) : Array(Tuple(String, LibTreeSitter::TSNode))
      values = [] of Tuple(String, LibTreeSitter::TSNode)
      Noir::TreeSitter.each_named_child(node) do |child|
        if Noir::TreeSitter.node_type(child) == "value_arguments"
          Noir::TreeSitter.each_named_child(child) do |arg|
            next unless Noir::TreeSitter.node_type(arg) == "value_argument"
            _, key, value_node = classify_value_argument(arg, source)
            values << {key, value_node} if value_node
          end
        else
          values.concat(annotation_argument_values(child, source))
        end
      end
      values
    end

    private def graphql_argument_type(params_node : LibTreeSitter::TSNode,
                                      source : String,
                                      start_index : Int32) : String
      count = LibTreeSitter.ts_node_named_child_count(params_node)
      index = start_index
      while index < count
        child = LibTreeSitter.ts_node_named_child(params_node, index.to_u32)
        case Noir::TreeSitter.node_type(child)
        when "user_type", "nullable_type"
          return Noir::TreeSitter.node_text(child, source).rstrip('?')
        when "parameter_modifiers", "simple_identifier"
          return "String"
        end
        index += 1
      end
      "String"
    end
  end
end
