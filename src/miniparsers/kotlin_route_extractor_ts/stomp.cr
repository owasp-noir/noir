# Part of Noir::TreeSitterKotlinRouteExtractor: STOMP endpoints and @MessageMapping destinations.
module Noir
  module TreeSitterKotlinRouteExtractor
    def extract_stomp_application_prefixes(source : String,
                                           string_constants = Hash(String, String).new,
                                           local_string_constants : Hash(String, String)? = nil) : Array(String)
      prefixes = [] of String
      file_constants = local_string_constants || extract_string_constants(source)
      each_method_call_arguments(source, "setApplicationDestinationPrefixes") do |args, _line|
        top_level_arguments(args).each do |arg|
          resolve_route_expressions(arg, string_constants, file_constants).each do |prefix|
            prefixes << prefix
          end
        end
      end
      prefixes.uniq
    end

    def extract_stomp_routes_from(root : LibTreeSitter::TSNode,
                                  source : String,
                                  string_constants = Hash(String, String).new,
                                  local_string_constants : Hash(String, String)? = nil,
                                  application_prefixes = [""]) : Array(Route)
      routes = [] of Route
      file_constants = local_string_constants || extract_string_constants(source)
      collect_stomp_handshake_routes(source, routes, string_constants, file_constants)
      walk_message_mapping_routes(root, source, string_constants, file_constants, application_prefixes, [""], routes)
      routes
    end

    private def collect_stomp_handshake_routes(source : String,
                                               routes : Array(Route),
                                               string_constants : Hash(String, String),
                                               local_string_constants : Hash(String, String))
      each_method_call_arguments(source, "addEndpoint") do |args, line|
        top_level_arguments(args).each do |arg|
          resolve_route_expressions(arg, string_constants, local_string_constants).each do |endpoint_path|
            routes << Route.new("GET", endpoint_path, "", "", line - 1)
          end
        end
      end
    end

    private def walk_message_mapping_routes(node : LibTreeSitter::TSNode,
                                            source : String,
                                            string_constants : Hash(String, String),
                                            local_string_constants : Hash(String, String),
                                            application_prefixes : Array(String),
                                            outer_prefixes : Array(String),
                                            routes : Array(Route),
                                            depth = 0,
                                            stray_annotation_nodes = [] of LibTreeSitter::TSNode)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      node_type = Noir::TreeSitter.node_type(node)
      if node_type == "class_declaration" || node_type == "object_declaration" || node_type == "interface_declaration"
        class_name = type_identifier_text(node, source)
        class_paths = message_mapping_paths(node, source, string_constants, local_string_constants, stray_annotation_nodes)
        class_paths = [""] if class_paths.empty?
        prefixes = [] of String
        outer_prefixes.each do |outer_prefix|
          class_paths.each do |class_path|
            prefixes << Noir::URLPath.join_absorbing(outer_prefix, class_path)
          end
        end

        if body = class_body(node)
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "function_declaration"
              collect_message_mapping_function_routes(
                member, source, class_name, prefixes, application_prefixes, routes, string_constants, local_string_constants
              )
            when "class_declaration", "object_declaration", "interface_declaration"
              walk_message_mapping_routes(
                member, source, string_constants, local_string_constants, application_prefixes, prefixes, routes, depth + 1
              )
            end
          end
        end
        return
      end

      pending = [] of LibTreeSitter::TSNode
      count = LibTreeSitter.ts_node_named_child_count(node)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(node, i.to_u32)
        case Noir::TreeSitter.node_type(child)
        when "class_declaration", "object_declaration", "interface_declaration"
          walk_message_mapping_routes(
            child, source, string_constants, local_string_constants, application_prefixes, outer_prefixes, routes, depth + 1, pending
          )
          pending = [] of LibTreeSitter::TSNode
        when "prefix_expression"
          if prefix_expression_has_annotation?(child)
            pending << child
          else
            pending = [] of LibTreeSitter::TSNode
            walk_message_mapping_routes(
              child, source, string_constants, local_string_constants, application_prefixes, outer_prefixes, routes, depth + 1
            )
          end
        else
          pending = [] of LibTreeSitter::TSNode
          walk_message_mapping_routes(
            child, source, string_constants, local_string_constants, application_prefixes, outer_prefixes, routes, depth + 1
          )
        end
      end
    end

    private def collect_message_mapping_function_routes(func : LibTreeSitter::TSNode,
                                                        source : String,
                                                        class_name : String,
                                                        class_prefixes : Array(String),
                                                        application_prefixes : Array(String),
                                                        routes : Array(Route),
                                                        string_constants : Hash(String, String),
                                                        local_string_constants : Hash(String, String))
      method_name = function_name(func, source)
      destinations = message_send_destinations(func, source, string_constants, local_string_constants)

      each_annotation(func, source) do |ann_name, args, ann_line|
        verb =
          case ann_name
          when "MessageMapping"   then "SEND"
          when "SubscribeMapping" then "SUBSCRIBE"
          end
        next unless verb

        paths = annotation_paths(args, source, string_constants, local_string_constants)
        paths = [""] if paths.empty?

        application_prefixes.each do |application_prefix|
          class_prefixes.each do |class_prefix|
            paths.each do |path|
              routes << Route.new(
                verb, Noir::URLPath.join_absorbing(application_prefix, Noir::URLPath.join_absorbing(class_prefix, path)), class_name, method_name, ann_line,
                messaging_destinations: destinations
              )
            end
          end
        end
      end
    end

    private def message_send_destinations(func : LibTreeSitter::TSNode,
                                          source : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : Array(String)
      destinations = [] of String
      each_annotation(func, source) do |name, args|
        next unless name == "SendTo" || name == "SendToUser"
        destinations.concat(annotation_paths(args, source, string_constants, local_string_constants))
      end
      destinations.uniq
    end

    private def message_mapping_paths(class_decl : LibTreeSitter::TSNode,
                                      source : String,
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String),
                                      stray_annotation_nodes : Array(LibTreeSitter::TSNode)) : Array(String)
      paths = [] of String
      each_annotation(class_decl, source) do |name, args|
        next unless name == "MessageMapping"
        paths.concat(annotation_paths(args, source, string_constants, local_string_constants))
      end

      stray_annotation_nodes.each do |stray|
        collect_stray_annotations(stray, source).each do |entry|
          name, args = entry
          next unless name == "MessageMapping"
          next unless args
          collect_string_values(args, source, paths, string_constants, local_string_constants)
        end
      end

      paths
    end
  end
end
