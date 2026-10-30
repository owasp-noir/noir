# Part of Noir::TreeSitterKotlinRouteExtractor: Armeria annotated services
# written in Kotlin (`@Get("/{id}")` on a method, `@PathPrefix` on the
# class). The Java side is walked inline by `Analyzer::Java::Armeria`; this
# returns the class-relative routes and leaves the `annotatedService(prefix,
# ...)` registration prefix to the analyzer, as the Java walk does.
#
# `@Param` is always emitted as a query param here; the analyzer drops the
# ones that name a `{var}` of the final, prefixed URL.
module Noir
  module TreeSitterKotlinRouteExtractor
    ARMERIA_VERB_ANNOTATIONS = {
      "Get" => "GET", "Post" => "POST", "Put" => "PUT", "Delete" => "DELETE",
      "Patch" => "PATCH", "Head" => "HEAD", "Options" => "OPTIONS", "Trace" => "TRACE",
    }

    record ArmeriaRoute, verb : String, path : String, class_name : String, line : Int32,
      params : Array(Param), callees : Array(Tuple(String, Int32))

    def extract_armeria_routes_from(root : LibTreeSitter::TSNode,
                                    source : String,
                                    dto_index : KotlinDtoIndex = KotlinDtoIndex.new,
                                    *,
                                    include_callees : Bool = false) : Array(ArmeriaRoute)
      routes = [] of ArmeriaRoute
      constants = expand_constant_interpolations(extract_string_constants(source))
      each_annotated_class(root, source) do |decl, annotations|
        class_name = type_identifier_text(decl, source)
        class_prefixes = [] of String
        annotations.each do |(name, args, _line)|
          class_prefixes.concat(annotation_values(args, source, constants, constants, {"value", "path"})) if name == "PathPrefix"
        end
        class_prefixes = [""] if class_prefixes.empty?
        body = class_body(decl)
        next unless body

        Noir::TreeSitter.each_named_child(body) do |member|
          next unless Noir::TreeSitter.node_type(member) == "function_declaration"
          verbs = [] of Tuple(String, Array(String), Int32)
          explicit_paths = [] of String
          each_annotation(member, source) do |name, args, line|
            if verb = ARMERIA_VERB_ANNOTATIONS[name]?
              verbs << {verb, annotation_values(args, source, constants, constants, {"value", "path"}), line}
            elsif name == "Path"
              explicit_paths.concat(annotation_values(args, source, constants, constants, {"value", "path"}))
            end
          end
          next if verbs.empty?

          params = armeria_params(member, source, dto_index, constants)
          callees = include_callees ? function_callees(member, source) : [] of Tuple(String, Int32)
          verbs.each do |(verb, paths, line)|
            (paths.empty? ? explicit_paths : paths).each do |method_path|
              class_prefixes.each do |prefix|
                routes << ArmeriaRoute.new(verb, Noir::URLPath.join_trimmed(prefix, method_path), class_name, line, params, callees)
              end
            end
          end
        end
      end
      routes
    end

    private def armeria_params(func : LibTreeSitter::TSNode,
                               source : String,
                               dto_index : KotlinDtoIndex,
                               constants : Hash(String, String)) : Array(Param)
      params = [] of Param
      each_function_parameter(func, source) do |param_name, type_node, annotations|
        default_value = ""
        annotations.each do |(name, args, _line)|
          default_value = annotation_values(args, source, constants, constants).first? || "" if name == "Default"
        end
        annotations.each do |(name, args, _line)|
          case name
          when "Param", "Header"
            bound = annotation_values(args, source, constants, constants, {"value", "name"}).first?
            params << Param.new(bound.presence || param_name, default_value, name == "Param" ? "query" : "header")
          when "RequestObject"
            type_name = resource_type_name(type_node, source)
            params.concat(dto_body_params(type_name, dto_index, "json") || [Param.new(param_name, "", "json")])
          end
        end
      end
      params
    end
  end
end
