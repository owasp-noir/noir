require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed Java route extractor.
  #
  # Scope for this first cut: Spring's annotation-based routing —
  # class-level `@RequestMapping`-family annotations composing with
  # method-level mapping annotations. This is the most common Java
  # route shape by a wide margin and what `src/analyzer/analyzers/java/
  # spring.cr` exists to surface. Covers:
  #
  #   * `@GetMapping`, `@PostMapping`, `@PutMapping`, `@DeleteMapping`,
  #     `@PatchMapping` — each fixes the HTTP verb
  #   * `@RequestMapping` — generic; verb comes from a `method =
  #     RequestMethod.X` element-value pair, or is reported as ANY when
  #     none is given because Spring matches all HTTP methods
  #   * Class-level mapping annotations contribute a prefix that's
  #     concatenated onto the per-method path
  #   * Annotation value supplied positionally (`@GetMapping("/x")`)
  #     or as a keyword element (`value = "/x"` / `path = "/x"`),
  #     including arrays
  #   * Same-file meta-annotations that compose Spring mapping
  #     annotations of their own
  #   * Multi-line annotations (the Java grammar eats whitespace for us)
  #
  # Deliberately not covered yet (handled by the legacy analyzer while
  # this PoC stabilises):
  #
  #   * Cross-file meta-annotation resolution
  #
  # Other JVM frameworks (Armeria, Play, JSP, Vert.x) can layer on top
  # of this once the Spring port is validated.
  module TreeSitterJavaRouteExtractor
    extend self

    # Spring mapping annotation names mapped to the HTTP verb they imply.
    # `nil` means "look at the annotation's `method =` argument".
    ANNOTATION_VERBS = {
      "GetMapping"     => "GET",
      "PostMapping"    => "POST",
      "PutMapping"     => "PUT",
      "DeleteMapping"  => "DELETE",
      "PatchMapping"   => "PATCH",
      "RequestMapping" => nil,
      "GetExchange"    => "GET",
      "PostExchange"   => "POST",
      "PutExchange"    => "PUT",
      "DeleteExchange" => "DELETE",
      "PatchExchange"  => "PATCH",
      "HttpExchange"   => nil,
    }

    struct Route
      getter verb : String        # upper-cased HTTP verb
      getter path : String        # full path (class prefix + method path)
      getter class_name : String  # enclosing class simple name, or ""
      getter method_name : String # Java method name, or "" when class-level only
      getter line : Int32         # 0-based line of the method annotation
      getter params : Array(Param)

      def initialize(@verb, @path, @class_name, @method_name, @line, @params = [] of Param)
      end
    end

    struct ClassMapping
      getter paths : Array(String)
      getter verbs : Array(String)
      getter params : Array(Param)

      def initialize(@paths, @verbs, @params = [] of Param)
      end
    end

    struct ControllerInterfaceImplementation
      getter class_name : String
      getter interface_names : Array(String)
      getter paths : Array(String)
      getter verbs : Array(String)
      getter params : Array(Param)
      getter line : Int32

      def initialize(@class_name, @interface_names, @paths, @verbs, @params, @line)
      end
    end

    private struct GatewayRoute
      getter verb : String
      getter path : String

      def initialize(@verb, @path)
      end
    end

    # Parses `source` and returns every Spring-style route it can
    # resolve. Top-level classes are scanned in order; nested classes
    # inherit their parent class's mapping prefix.
    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        routes = extract_routes_from(root, source)
      end
      routes
    end

    def extract_string_constants(source : String) : Hash(String, String)
      constants = Hash(String, String).new
      Noir::TreeSitter.parse_java(source) do |root|
        constants = extract_string_constants_from(root, source)
      end
      constants
    end

    # `_from` variant — accept a pre-parsed `root` so the Spring
    # analyzer can amortise tree-sitter parses across multiple
    # extractions on the same file. Tree lifetime is the caller's
    # responsibility.
    def extract_routes_from(root : LibTreeSitter::TSNode,
                            source : String,
                            external_meta_mappings = Hash(String, ClassMapping).new) : Array(Route)
      routes = [] of Route
      constants = extract_string_constants_from(root, source)
      meta_mappings = external_meta_mappings.dup
      collect_meta_mappings(root, source, constants, meta_mappings)
      walk_classes(root, source, [""], [] of String, [] of Param, routes, constants, meta_mappings)
      collect_gateway_routes(source, constants, routes)
      routes
    end

    def extract_meta_mappings_from(root : LibTreeSitter::TSNode,
                                   source : String,
                                   constants : Hash(String, String)? = nil) : Hash(String, ClassMapping)
      mappings = Hash(String, ClassMapping).new
      collect_meta_mappings(root, source, constants || extract_string_constants_from(root, source), mappings)
      mappings
    end

    def extract_interface_routes_from(root : LibTreeSitter::TSNode,
                                      source : String,
                                      external_meta_mappings = Hash(String, ClassMapping).new) : Hash(String, Array(Route))
      constants = extract_string_constants_from(root, source)
      meta_mappings = external_meta_mappings.dup
      collect_meta_mappings(root, source, constants, meta_mappings)
      routes = Hash(String, Array(Route)).new { |hash, key| hash[key] = [] of Route }
      walk_interface_routes(root, source, routes, constants, meta_mappings)
      routes
    end

    def extract_controller_interface_implementations_from(root : LibTreeSitter::TSNode,
                                                          source : String,
                                                          external_meta_mappings = Hash(String, ClassMapping).new) : Array(ControllerInterfaceImplementation)
      constants = extract_string_constants_from(root, source)
      meta_mappings = external_meta_mappings.dup
      collect_meta_mappings(root, source, constants, meta_mappings)
      implementations = [] of ControllerInterfaceImplementation
      walk_controller_interface_implementations(root, source, implementations, constants, meta_mappings)
      implementations
    end

    def extract_string_constants_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      constants = Hash(String, String).new
      collect_string_constants(root, source, package_name(root, source), [] of String, constants)
      constants
    end

    # ---- private helpers ----------------------------------------------

    # Walk every class/interface declaration (including nested). Interfaces
    # are relevant for Spring Cloud Feign (`@FeignClient` + method
    # `@*Mapping` annotations) and Spring HTTP Interface clients
    # (`@HttpExchange` / `@*Exchange`). `outer_prefix` is the path prefix
    # accumulated from enclosing scopes.
    private def walk_classes(node : LibTreeSitter::TSNode,
                             source : String,
                             outer_prefixes : Array(String),
                             outer_verbs : Array(String),
                             outer_params : Array(Param),
                             routes : Array(Route),
                             constants : Hash(String, String),
                             meta_mappings : Hash(String, ClassMapping))
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration"
        if ty == "interface_declaration" && !endpoint_interface?(node, source)
          return
        end

        # An `abstract` base is never mapped directly — its routes only
        # exist through a concrete subclass (resolved separately via the
        # inherited-route index). Walk into it for nested types but don't
        # emit its own method routes, otherwise an un-prefixed phantom
        # endpoint (e.g. `GET /list` for `BaseController.list`) leaks.
        is_abstract = ty == "class_declaration" && abstract_class?(node, source)

        class_name = class_simple_name(node, source)
        mapping = class_mapping(node, source, constants, class_name, meta_mappings)
        class_prefixes = mapping.paths
        class_prefixes = [""] if class_prefixes.empty?
        prefixes = [] of String
        outer_prefixes.each do |outer_prefix|
          class_prefixes.each do |class_prefix|
            prefixes << join_paths(outer_prefix, class_prefix)
          end
        end
        verbs = (outer_verbs + mapping.verbs).uniq
        params = outer_params + mapping.params

        if body = Noir::TreeSitter.field(node, "body")
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "method_declaration"
              collect_method_routes(member, source, class_name, prefixes, verbs, params, routes, constants, meta_mappings) unless is_abstract
            when "class_declaration", "interface_declaration"
              walk_classes(member, source, prefixes, verbs, params, routes, constants, meta_mappings)
            end
          end
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_classes(child, source, outer_prefixes, outer_verbs, outer_params, routes, constants, meta_mappings)
      end
    end

    private def walk_interface_routes(node : LibTreeSitter::TSNode,
                                      source : String,
                                      routes : Hash(String, Array(Route)),
                                      constants : Hash(String, String),
                                      meta_mappings : Hash(String, ClassMapping),
                                      depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      # Both interfaces and `abstract` base classes can declare routes
      # that a concrete controller inherits, so index either under its
      # simple name.
      ty = Noir::TreeSitter.node_type(node)
      indexable = ty == "interface_declaration" || (ty == "class_declaration" && abstract_class?(node, source))
      if indexable
        type_name = class_simple_name(node, source)
        mapping = class_mapping(node, source, constants, type_name, meta_mappings)
        prefixes = mapping.paths
        prefixes = [""] if prefixes.empty?

        if body = Noir::TreeSitter.field(node, "body")
          Noir::TreeSitter.each_named_child(body) do |member|
            next unless Noir::TreeSitter.node_type(member) == "method_declaration"
            collect_method_routes(member, source, type_name, prefixes, mapping.verbs, mapping.params, routes[type_name], constants, meta_mappings)
          end
        end
        # Interfaces never enclose a controller; an abstract class might
        # nest one, so keep descending for the class case.
        return if ty == "interface_declaration"
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_interface_routes(child, source, routes, constants, meta_mappings, depth + 1)
      end
    end

    private def walk_controller_interface_implementations(node : LibTreeSitter::TSNode,
                                                          source : String,
                                                          implementations : Array(ControllerInterfaceImplementation),
                                                          constants : Hash(String, String),
                                                          meta_mappings : Hash(String, ClassMapping),
                                                          depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "class_declaration"
        interface_names = implemented_interface_names(node, source)
        # A concrete controller can also inherit `@*Mapping` methods from
        # an `abstract` base class (generic CRUD bases are common). Treat
        # the superclass exactly like an implemented interface — its
        # routes are resolved from the same index.
        if superclass = superclass_name(node, source)
          interface_names << superclass unless interface_names.includes?(superclass)
        end
        if !interface_names.empty? && spring_controller_class?(node, source)
          class_name = class_simple_name(node, source)
          mapping = class_mapping(node, source, constants, class_name, meta_mappings)
          paths = mapping.paths
          paths = [""] if paths.empty?
          implementations << ControllerInterfaceImplementation.new(
            class_name, interface_names, paths, mapping.verbs, mapping.params, Noir::TreeSitter.node_start_row(node)
          )
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_controller_interface_implementations(child, source, implementations, constants, meta_mappings, depth + 1)
      end
    end

    private def class_simple_name(class_decl : LibTreeSitter::TSNode, source : String) : String
      if name_node = Noir::TreeSitter.field(class_decl, "name")
        return Noir::TreeSitter.node_text(name_node, source)
      end
      ""
    end

    private def endpoint_interface?(decl : LibTreeSitter::TSNode, source : String) : Bool
      return true if annotated_with_any?(decl, source, Set{"FeignClient", "Controller", "RestController", "HttpExchange"})
      has_exchange_mapping_method?(decl, source)
    end

    private def spring_controller_class?(decl : LibTreeSitter::TSNode, source : String) : Bool
      annotated_with_any?(decl, source, Set{"Controller", "RestController"})
    end

    private def annotated_with_any?(decl : LibTreeSitter::TSNode, source : String, names : Set(String)) : Bool
      each_annotation(decl, source) do |name, _args, _line|
        return true if names.includes?(name)
      end
      false
    end

    private def has_exchange_mapping_method?(decl : LibTreeSitter::TSNode, source : String) : Bool
      return false unless body = Noir::TreeSitter.field(decl, "body")

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        each_annotation(member, source) do |name, _args, _line|
          return true if exchange_mapping_annotation?(name)
        end
      end

      false
    end

    private def exchange_mapping_annotation?(name : String) : Bool
      name == "HttpExchange" || name.ends_with?("Exchange")
    end

    private def implemented_interface_names(class_decl : LibTreeSitter::TSNode, source : String) : Array(String)
      header = Noir::TreeSitter.node_text(class_decl, source)
      if body_start = header.index('{')
        header = header[...body_start]
      end

      match = header.match(/\bimplements\s+(.+)\z/m)
      return [] of String unless match

      names = split_top_level_commas(match[1]).compact_map do |raw|
        type_name = raw.strip
        next if type_name.empty?
        type_name = strip_generic_arguments(type_name)
        type_name = type_name.split(/\s+/).first? || type_name
        if idx = type_name.rindex('.')
          type_name[(idx + 1)..]
        else
          type_name
        end
      end
      names.uniq!
      names
    end

    # An `abstract class` is never instantiated as a controller, so its
    # `@*Mapping` methods are only ever served through a concrete
    # subclass. We use this both to suppress the base's standalone routes
    # and to index it as an inheritable route source.
    private def abstract_class?(decl : LibTreeSitter::TSNode, source : String) : Bool
      return false unless mods = find_modifiers(decl)
      Noir::TreeSitter.node_text(mods, source).split.includes?("abstract")
    end

    # Simple name of the `extends` superclass, or nil. Read straight from
    # the tree-sitter `superclass` field so neither class-level annotation
    # arguments nor `<T extends Number>` type-parameter bounds can confuse
    # the parse; generic arguments on the parent type (`Parent<T>`) are
    # stripped, and a qualified name keeps only its last segment.
    private def superclass_name(class_decl : LibTreeSitter::TSNode, source : String) : String?
      return unless superclass = Noir::TreeSitter.field(class_decl, "superclass")
      return unless LibTreeSitter.ts_node_named_child_count(superclass) > 0

      type_node = LibTreeSitter.ts_node_named_child(superclass, 0_u32)
      name = strip_generic_arguments(Noir::TreeSitter.node_text(type_node, source))
      return if name.empty?

      if idx = name.rindex('.')
        name[(idx + 1)..]
      else
        name
      end
    end

    private def split_top_level_commas(text : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      text.each_char_with_index do |char, index|
        case char
        when '<'
          depth += 1
        when '>'
          depth -= 1 if depth > 0
        when ','
          if depth == 0
            parts << text[start...index]
            start = index + 1
          end
        end
      end
      parts << text[start..]
      parts
    end

    private def strip_generic_arguments(text : String) : String
      String.build do |io|
        depth = 0
        text.each_char do |char|
          case char
          when '<'
            depth += 1
          when '>'
            depth -= 1 if depth > 0
          else
            io << char if depth == 0
          end
        end
      end.strip
    end

    # Pull class-level `@RequestMapping(...)` / `@GetMapping(...)`
    # path contributions. Spring treats `value` / `path` as `String[]`,
    # so class-level arrays fan out across every method-level mapping.
    private def class_mapping(class_decl : LibTreeSitter::TSNode,
                              source : String,
                              constants : Hash(String, String),
                              class_name : String,
                              meta_mappings : Hash(String, ClassMapping)) : ClassMapping
      each_annotation(class_decl, source) do |name, args_node|
        mapping = mapping_from_annotation(name, args_node, source, constants, class_name, meta_mappings)
        next unless mapping

        return mapping unless mapping.paths.empty?
        return mapping if annotation_has_path_argument?(args_node, source) || !mapping.verbs.empty?
      end
      ClassMapping.new([] of String, [] of String)
    end

    private def collect_method_routes(method : LibTreeSitter::TSNode,
                                      source : String,
                                      class_name : String,
                                      class_prefixes : Array(String),
                                      class_verbs : Array(String),
                                      class_params : Array(Param),
                                      routes : Array(Route),
                                      constants : Hash(String, String),
                                      meta_mappings : Hash(String, ClassMapping))
      method_name = ""
      if name_node = Noir::TreeSitter.field(method, "name")
        method_name = Noir::TreeSitter.node_text(name_node, source)
      end

      each_annotation(method, source) do |ann_name, args_node, ann_line|
        direct_verb_default = ANNOTATION_VERBS[ann_name]?
        direct_mapping = ANNOTATION_VERBS.has_key?(ann_name)
        meta_mapping = meta_mappings[ann_name]?
        next unless direct_mapping || meta_mapping

        route_params = class_params + mapping_condition_params(args_node, source, constants, class_name)
        route_params = route_params + meta_mapping.params if meta_mapping
        paths = annotation_paths(args_node, source, constants, class_name)
        paths = meta_mapping.paths if paths.empty? && meta_mapping
        next if paths.empty? && annotation_has_path_argument?(args_node, source)
        paths = [""] if paths.empty?

        verbs =
          if direct_mapping && direct_verb_default
            [direct_verb_default]
          elsif direct_mapping
            methods = annotation_methods(args_node, source)
            methods.empty? ? (class_verbs.empty? ? ["ANY"] : class_verbs) : (class_verbs + methods).uniq
          elsif meta_mapping && !meta_mapping.verbs.empty?
            meta_mapping.verbs
          else
            class_verbs.empty? ? ["ANY"] : class_verbs
          end

        verbs = (class_verbs + verbs).uniq if direct_verb_default && !class_verbs.empty?

        # Fan out into every (path × verb) combination. Spring's
        # `@RequestMapping({"/a", "/b"}, method = {GET, POST})` emits
        # four routes.
        paths.each do |path|
          class_prefixes.each do |class_prefix|
            full = join_paths(class_prefix, path)
            verbs.each do |verb|
              routes << Route.new(verb, full, class_name, method_name, ann_line, route_params)
            end
          end
        end
      end
    end

    private def collect_meta_mappings(root : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String)) : Hash(String, ClassMapping)
      mappings = Hash(String, ClassMapping).new
      collect_meta_mappings(root, source, constants, mappings)
      mappings
    end

    private def collect_meta_mappings(node : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String),
                                      mappings : Hash(String, ClassMapping),
                                      depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "annotation_type_declaration"
        name = class_simple_name(node, source)
        unless name.empty?
          each_annotation(node, source) do |ann_name, args_node|
            next unless ANNOTATION_VERBS.has_key?(ann_name)
            mappings[name] = direct_mapping_from_annotation(ann_name, args_node, source, constants, name)
            break
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_meta_mappings(child, source, constants, mappings, depth + 1)
      end
    end

    private def mapping_from_annotation(name : String,
                                        args_node : LibTreeSitter::TSNode?,
                                        source : String,
                                        constants : Hash(String, String),
                                        class_name : String,
                                        meta_mappings : Hash(String, ClassMapping)) : ClassMapping?
      if ANNOTATION_VERBS.has_key?(name)
        return direct_mapping_from_annotation(name, args_node, source, constants, class_name)
      end

      return unless meta_mapping = meta_mappings[name]?

      usage_paths = annotation_paths(args_node, source, constants, class_name)
      paths = usage_paths.empty? ? meta_mapping.paths : usage_paths
      params = meta_mapping.params + mapping_condition_params(args_node, source, constants, class_name)
      ClassMapping.new(paths, meta_mapping.verbs, params)
    end

    private def direct_mapping_from_annotation(name : String,
                                               args_node : LibTreeSitter::TSNode?,
                                               source : String,
                                               constants : Hash(String, String),
                                               class_name : String) : ClassMapping
      verb_default = ANNOTATION_VERBS[name]?
      paths = annotation_paths(args_node, source, constants, class_name)
      verbs = if verb_default
                [verb_default]
              else
                annotation_methods(args_node, source)
              end
      params = mapping_condition_params(args_node, source, constants, class_name)

      ClassMapping.new(paths, verbs, params)
    end

    private def collect_gateway_routes(source : String,
                                       constants : Hash(String, String),
                                       routes : Array(Route))
      return unless source.includes?("RouteLocatorBuilder") ||
                    source.includes?("PredicateSpec") ||
                    source.includes?("org.springframework.cloud.gateway")

      visible_source = visible_java_code(source)
      helpers = gateway_predicate_helpers(source, visible_source, constants)

      scan_gateway_route_calls(source, visible_source) do |expr, line|
        gateway_routes_from_expression(expr, constants).each do |route|
          routes << Route.new(route.verb, route.path, "", "", line)
        end

        helpers.each do |name, helper_route|
          next unless expr.includes?("#{name}(") || expr.includes?(".#{name}(")
          routes << Route.new(helper_route.verb, helper_route.path, "", "", line)
        end
      end
    end

    private def scan_gateway_route_calls(source : String, visible_source : String, &)
      offset = 0
      while found = visible_source.index(".route", offset)
        open_idx = visible_source.index('(', found)
        break unless open_idx
        close_idx = find_matching_delimiter(visible_source, open_idx, '(', ')')
        if close_idx
          expr = source[open_idx..close_idx]
          # open_idx is a CHAR index; char-slice for the line count too.
          line = source[0, open_idx].count('\n')
          yield expr, line
          offset = close_idx + 1
        else
          offset = open_idx + 1
        end
      end
    end

    private def gateway_predicate_helpers(source : String,
                                          visible_source : String,
                                          constants : Hash(String, String)) : Hash(String, GatewayRoute)
      helpers = Hash(String, GatewayRoute).new
      pattern = /\b(?:public|protected|private|static|\s|final)*[A-Za-z_][A-Za-z0-9_<>, ?\[\].]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\bPredicateSpec\b[^)]*\)\s*\{/
      offset = 0

      while match = visible_source.match(pattern, offset)
        name = match[1]
        open_idx = visible_source.index('{', match.begin(0))
        break unless open_idx
        close_idx = find_matching_delimiter(visible_source, open_idx, '{', '}')
        if close_idx
          body = source[open_idx..close_idx]
          if route = gateway_routes_from_expression(body, constants).first?
            helpers[name] = route
          end
          offset = close_idx + 1
        else
          offset = open_idx + 1
        end
      end

      helpers
    end

    private def gateway_routes_from_expression(expr : String,
                                               constants : Hash(String, String)) : Array(GatewayRoute)
      paths = gateway_paths_from_expression(expr, constants)
      return [] of GatewayRoute if paths.empty?

      verbs = gateway_verbs_from_expression(expr)
      verbs = ["ANY"] if verbs.empty?

      routes = [] of GatewayRoute
      verbs.each do |verb|
        paths.each do |path|
          routes << GatewayRoute.new(verb, path)
        end
      end
      routes
    end

    private def gateway_verbs_from_expression(expr : String) : Array(String)
      verbs = [] of String
      expr.scan(/\bmethod\s*\(([^)]*)\)/m) do |match|
        match[1].scan(/(?:HttpMethod|RequestMethod)\.([A-Z]+)/) do |verb_match|
          verbs << verb_match[1]
        end
      end
      verbs.uniq
    end

    private def gateway_paths_from_expression(expr : String,
                                              constants : Hash(String, String)) : Array(String)
      paths = [] of String
      offset = 0
      while found = expr.index(".path", offset)
        open_idx = expr.index('(', found)
        break unless open_idx
        close_idx = find_matching_delimiter(expr, open_idx, '(', ')')
        if close_idx
          args = expr[(open_idx + 1)...close_idx]
          split_gateway_args(args).each do |raw|
            path = resolve_gateway_path(raw, constants)
            paths << path unless path.empty?
          end
          offset = close_idx + 1
        else
          offset = open_idx + 1
        end
      end
      paths.uniq
    end

    private def split_gateway_args(args : String) : Array(String)
      # Char-indexed: `args` may contain multi-byte path literals, so a byte loop
      # with char slices (`args[start...i]`) mis-slices and can raise IndexError.
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      escape = false
      args.each_char_with_index do |char, i|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
        else
          case char
          when '"'
            in_string = true
          when '(', '[', '{'
            depth += 1
          when ')', ']', '}'
            depth -= 1 if depth > 0
          when ','
            if depth == 0
              parts << args[start...i].strip
              start = i + 1
            end
          end
        end
      end
      parts << args[start..].strip
      parts.reject(&.empty?)
    end

    private def resolve_gateway_path(raw : String, constants : Hash(String, String)) : String
      value = raw.strip
      if match = value.match(/^"([^"]*)"$/)
        return match[1]
      end

      if resolved = constants[value]?
        return resolved
      end

      if idx = value.rindex('.')
        short_name = value[(idx + 1)..]
        if resolved = constants[short_name]?
          return resolved
        end
      end

      ""
    end

    private def visible_java_code(source : String) : String
      # Blank out comments and string/char literals (so their contents can't be
      # mistaken for code), emitting exactly ONE output char per input char so
      # char positions stay aligned with `source` — the gateway scan derives
      # char indices here and char-slices `source` with them.
      chars = source.chars
      mode = :code
      quote = '\0'
      escaped = false
      i = 0

      String.build(source.bytesize) do |io|
        while i < chars.size
          char = chars[i]

          case mode
          when :line_comment
            if char == '\n'
              io << char
              mode = :code
            else
              io << ' '
            end
            i += 1
          when :block_comment
            if char == '\n'
              io << char
              i += 1
            elsif char == '*' && chars[i + 1]? == '/'
              io << ' '
              io << ' '
              i += 2
              mode = :code
            else
              io << ' '
              i += 1
            end
          when :string
            if char == quote && !escaped
              io << ' '
              i += 1
              mode = :code
            else
              io << (char == '\n' ? '\n' : ' ')
              if escaped
                escaped = false
              else
                escaped = char == '\\'
              end
              i += 1
            end
          else
            if char == '/' && chars[i + 1]? == '/'
              io << ' '
              io << ' '
              i += 2
              mode = :line_comment
            elsif char == '/' && chars[i + 1]? == '*'
              io << ' '
              io << ' '
              i += 2
              mode = :block_comment
            elsif char == '"' || char == '\''
              io << ' '
              quote = char
              escaped = false
              i += 1
              mode = :string
            else
              io << char
              i += 1
            end
          end
        end
      end
    end

    private def find_matching_delimiter(code : String,
                                        open_idx : Int32,
                                        open_char : Char,
                                        close_char : Char) : Int32?
      # Char-indexed (open_idx comes from char-based String#index and the result
      # is char-sliced by callers). visible_java_code preserves char positions,
      # so char index N in visible_source == char index N in source. ASCII-identical.
      depth = 1
      in_string = false
      quote = '\0'
      escape = false
      result = nil

      code.each_char_with_index do |char, i|
        next if i <= open_idx
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
        else
          if char == '"' || char == '\''
            in_string = true
            quote = char
          elsif char == open_char
            depth += 1
          elsif char == close_char
            depth -= 1
          end
        end
        if depth == 0
          result = i
          break
        end
      end

      result
    end

    # Iterate annotations attached to a declaration. Yields
    # `(name, args_node_or_nil, line)` for each annotation.
    # Supports `marker_annotation` (no args) and `annotation` (with args).
    private def each_annotation(decl : LibTreeSitter::TSNode, source : String, &)
      mods = find_modifiers(decl)
      return unless mods

      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        name_node = Noir::TreeSitter.field(ann, "name")
        next unless name_node
        # `@foo.Bar` comes through as a scoped identifier; take the
        # last segment so the mapping-annotation lookup matches.
        name = simple_annotation_name(name_node, source)
        args = Noir::TreeSitter.field(ann, "arguments")
        yield name, args, Noir::TreeSitter.node_start_row(ann)
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

    private def simple_annotation_name(name_node : LibTreeSitter::TSNode, source : String) : String
      text = Noir::TreeSitter.node_text(name_node, source)
      if idx = text.rindex('.')
        text[(idx + 1)..]
      else
        text
      end
    end

    # Extract route paths from an annotation's argument list. Accepts
    # any combination of:
    #   - bare string literal `@GetMapping("/x")`
    #   - bare array `@RequestMapping({"/a", "/b"})`
    #   - `value = "..."` / `path = "..."` / `url = "..."` keyword forms of either
    #
    # Always returns an array. Empty when the annotation has no
    # path-like argument. Callers fan out into one endpoint per path.
    private def annotation_paths(args_node : LibTreeSitter::TSNode?,
                                 source : String,
                                 constants : Hash(String, String),
                                 current_class : String = "") : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "annotation_argument_list"

      positional = [] of String
      keyword = [] of String
      Noir::TreeSitter.each_named_child(args_node) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal", "identifier", "field_access", "binary_expression", "parenthesized_expression"
          collect_string_values(arg, source, constants, positional, current_class)
        when "element_value_array_initializer"
          collect_string_values(arg, source, constants, positional, current_class)
        when "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key")
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          k = Noir::TreeSitter.node_text(key, source)
          next unless k == "value" || k == "path" || k == "url"
          collect_string_values(val, source, constants, keyword, current_class)
        when "ERROR"
          # `@RequestMapping("/x", method = RequestMethod.GET)` is a
          # positional+keyword mix that Java technically disallows, but
          # the legacy analyzer (and idiomatic Spring code in the wild)
          # tolerate it. tree-sitter flags it as an `ERROR` node; recover
          # any string literal inside so we don't regress on fixtures
          # using this shape.
          collect_string_values(arg, source, constants, positional, current_class)
        end
      end
      keyword.empty? ? positional : keyword
    end

    private def annotation_has_path_argument?(args_node : LibTreeSitter::TSNode?, source : String) : Bool
      return false unless args_node
      return false unless Noir::TreeSitter.node_type(args_node) == "annotation_argument_list"

      Noir::TreeSitter.each_named_child(args_node) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal", "identifier", "field_access", "binary_expression", "parenthesized_expression",
             "element_value_array_initializer", "ERROR"
          return true
        when "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key")
          next unless key
          k = Noir::TreeSitter.node_text(key, source)
          return true if k == "value" || k == "path" || k == "url"
        end
      end

      false
    end

    private def mapping_condition_params(args_node : LibTreeSitter::TSNode?,
                                         source : String,
                                         constants : Hash(String, String),
                                         current_class : String = "") : Array(Param)
      params = [] of Param
      annotation_string_values_for_keys(args_node, Set{"params"}, source, constants, current_class).each do |expr|
        if param = condition_param(expr, "query")
          params << param
        end
      end
      annotation_string_values_for_keys(args_node, Set{"headers"}, source, constants, current_class).each do |expr|
        if param = condition_param(expr, "header")
          params << param
        end
      end
      params.uniq { |param| {param.name, param.param_type, param.value} }
    end

    private def annotation_string_values_for_keys(args_node : LibTreeSitter::TSNode?,
                                                  keys : Set(String),
                                                  source : String,
                                                  constants : Hash(String, String),
                                                  current_class : String = "") : Array(String)
      values = [] of String
      return values unless args_node
      return values unless Noir::TreeSitter.node_type(args_node) == "annotation_argument_list"

      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "element_value_pair"
        key = Noir::TreeSitter.field(arg, "key")
        val = Noir::TreeSitter.field(arg, "value")
        next unless key && val
        next unless keys.includes?(Noir::TreeSitter.node_text(key, source))
        collect_string_values(val, source, constants, values, current_class)
      end
      values
    end

    private def condition_param(expr : String, param_type : String) : Param?
      condition = expr.strip
      return if condition.empty? || condition.starts_with?("!")

      if idx = condition.index("!=")
        name = condition[...idx].strip
        return if name.empty?
        return Param.new(name, "", param_type)
      end

      if idx = condition.index('=')
        name = condition[...idx].strip
        value = condition[(idx + 1)..].strip
        return if name.empty?
        return Param.new(name, value, param_type)
      end

      Param.new(condition, "", param_type)
    end

    # Known HTTP-verb identifiers we consider valid `method = ...` values.
    # Used when reconstructing verbs from ERROR nodes around the
    # invalid `[...]` bracket syntax.
    VERB_IDENTIFIERS = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"}

    # Extract verbs from an annotation's `method = ...` argument.
    # Supports the single form (`method = RequestMethod.GET`) and the
    # array form (`method = {RequestMethod.GET, RequestMethod.POST}`).
    # Returns an empty array when `method` is absent.
    private def annotation_methods(args_node : LibTreeSitter::TSNode?, source : String) : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "annotation_argument_list"

      methods = [] of String
      saw_method_pair = false
      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "element_value_pair"
        key = Noir::TreeSitter.field(arg, "key")
        val = Noir::TreeSitter.field(arg, "value")
        next unless key && val
        next unless Noir::TreeSitter.node_text(key, source) == "method"
        saw_method_pair = true
        case Noir::TreeSitter.node_type(val)
        when "string_literal"
          method = decode_string_literal(val, source).upcase
          methods << method if VERB_IDENTIFIERS.includes?(method)
        when "field_access"
          if f = Noir::TreeSitter.field(val, "field")
            methods << Noir::TreeSitter.node_text(f, source).upcase
          end
        when "identifier"
          methods << Noir::TreeSitter.node_text(val, source).upcase
        when "element_value_array_initializer"
          Noir::TreeSitter.each_named_child(val) do |elem|
            case Noir::TreeSitter.node_type(elem)
            when "field_access"
              if f = Noir::TreeSitter.field(elem, "field")
                methods << Noir::TreeSitter.node_text(f, source).upcase
              end
            when "identifier"
              methods << Noir::TreeSitter.node_text(elem, source).upcase
            end
          end
        end
      end

      # Recover `method = [RequestMethod.GET, RequestMethod.POST]` — the
      # `[...]` bracket form is invalid Java (only `{...}` is legal) and
      # tree-sitter scatters the trailing entries into sibling ERROR
      # nodes. The legacy analyzer tolerated this because its lenient
      # lexer didn't care. Only run this recovery when we already
      # confirmed a `method = ...` pair existed to minimise false
      # positives from unrelated ERROR nodes.
      if saw_method_pair
        Noir::TreeSitter.each_named_child(args_node) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "ERROR"
          Noir::TreeSitter.each_named_child(arg) do |inner|
            next unless Noir::TreeSitter.node_type(inner) == "identifier"
            text = Noir::TreeSitter.node_text(inner, source).upcase
            methods << text if VERB_IDENTIFIERS.includes?(text)
          end
        end
      end

      methods.uniq
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      buf
    end

    private def package_name(root : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(root) do |child|
        next unless Noir::TreeSitter.node_type(child) == "package_declaration"
        text = Noir::TreeSitter.node_text(child, source)
        if match = text.match(/\A\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)/)
          return match[1]
        end
      end
      ""
    end

    private def collect_string_constants(node : LibTreeSitter::TSNode,
                                         source : String,
                                         package_name : String,
                                         class_stack : Array(String),
                                         constants : Hash(String, String),
                                         depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration" || ty == "enum_declaration" || ty == "annotation_type_declaration"
        name = class_simple_name(node, source)
        next_stack = name.empty? ? class_stack : class_stack + [name]
        Noir::TreeSitter.each_named_child(node) do |child|
          collect_string_constants(child, source, package_name, next_stack, constants, depth + 1)
        end
        return
      end

      if ty == "field_declaration" && string_field?(node, source)
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "variable_declarator"
          name = Noir::TreeSitter.field(child, "name")
          value = Noir::TreeSitter.field(child, "value")
          next unless name && value
          const_name = Noir::TreeSitter.node_text(name, source)
          next unless resolved = resolve_string_value(value, source, constants, class_stack.join("."))

          constants[const_name] ||= resolved
          unless class_stack.empty?
            class_name = class_stack.join(".")
            constants["#{class_name}.#{const_name}"] ||= resolved
            constants["#{package_name}.#{class_name}.#{const_name}"] ||= resolved unless package_name.empty?
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_string_constants(child, source, package_name, class_stack, constants, depth + 1)
      end
    end

    private def string_field?(field_decl : LibTreeSitter::TSNode, source : String) : Bool
      if type_node = Noir::TreeSitter.field(field_decl, "type")
        type_text = Noir::TreeSitter.node_text(type_node, source)
        return type_text == "String" || type_text == "java.lang.String"
      end

      Noir::TreeSitter.each_named_child(field_decl) do |child|
        next unless Noir::TreeSitter.node_type(child) == "type_identifier" || Noir::TreeSitter.node_type(child) == "scoped_type_identifier"
        type_text = Noir::TreeSitter.node_text(child, source)
        return true if type_text == "String" || type_text == "java.lang.String"
      end
      false
    end

    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String),
                                      sink : Array(String),
                                      current_class : String = "")
      case Noir::TreeSitter.node_type(node)
      when "element_value_array_initializer", "ERROR"
        Noir::TreeSitter.each_named_child(node) do |child|
          collect_string_values(child, source, constants, sink, current_class)
        end
      else
        if resolved = resolve_string_value(node, source, constants, current_class)
          sink << resolved
        end
      end
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     constants : Hash(String, String),
                                     current_class : String = "",
                                     depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "identifier", "field_access"
        resolve_constant_reference(Noir::TreeSitter.node_text(node, source), constants, current_class)
      when "binary_expression"
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        return unless Noir::TreeSitter.node_text(node, source).includes?("+")
        left_value = resolve_string_value(left, source, constants, current_class, depth + 1)
        right_value = resolve_string_value(right, source, constants, current_class, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_string_value(child, source, constants, current_class, depth + 1)
            return value
          end
        end
      end
    end

    private def resolve_constant_reference(name : String,
                                           constants : Hash(String, String),
                                           current_class : String = "") : String?
      unless name.includes?(".") || current_class.empty?
        if resolved = constants["#{current_class}.#{name}"]?
          return resolved
        end
      end

      if resolved = constants[name]?
        return resolved
      end

      nil
    end

    # Join a class prefix and a method path with exactly one `/`. Also
    # handles the leading-slash ambiguity Spring is famously relaxed
    # about: `@RequestMapping("items")` + `@GetMapping("{id}")` maps to
    # `/items/{id}` even though neither segment has a leading slash.
    #
    # Empty method path (`@PostMapping` with no argument, or
    # `@GetMapping("")`) collapses onto the class prefix — Spring absorbs
    # the empty segment, so `@RequestMapping("/api")` + `@GetMapping`
    # maps to `/api`, not `/api/` (see the empty-path branch below).
    private def join_paths(prefix : String, path : String) : String
      return path if prefix.empty?
      # A bare method mapping (`@GetMapping` / `@GetMapping("")`) on a
      # class mapped to `/api/polls` resolves to `/api/polls` in Spring,
      # NOT `/api/polls/` — the empty segment is absorbed into the class
      # prefix. Mirror the jaxrs/quarkus/micronaut extractors and drop
      # the trailing slash here; only a class prefix that is itself all
      # slashes (`@RequestMapping("/")`) keeps the root `/`.
      if path.empty?
        trimmed = prefix.rstrip('/')
        return trimmed.empty? ? "/" : trimmed
      end
      trimmed_prefix = prefix.rstrip('/')
      trimmed_path = path.lstrip('/')
      "#{trimmed_prefix}/#{trimmed_path}"
    end
  end
end
