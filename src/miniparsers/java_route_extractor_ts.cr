require "../ext/tree_sitter/tree_sitter"

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
  #     RequestMethod.X` element-value pair, or defaults to GET when
  #     none is given
  #   * Class-level mapping annotations contribute a prefix that's
  #     concatenated onto the per-method path
  #   * Annotation value supplied positionally (`@GetMapping("/x")`)
  #     or as a keyword element (`value = "/x"` / `path = "/x"`)
  #   * Multi-line annotations (the Java grammar eats whitespace for us)
  #
  # Deliberately not covered yet (handled by the legacy analyzer while
  # this PoC stabilises):
  #
  #   * Meta-annotations (custom annotations that compose mapping
  #     annotations of their own)
  #   * Arrays of paths: `@RequestMapping({"/a", "/b"})` currently
  #     emits only the first path. Follow-up to iterate each literal.
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
    }

    struct Route
      getter verb : String        # upper-cased HTTP verb
      getter path : String        # full path (class prefix + method path)
      getter class_name : String  # enclosing class simple name, or ""
      getter method_name : String # Java method name, or "" when class-level only
      getter line : Int32         # 0-based line of the method annotation

      def initialize(@verb, @path, @class_name, @method_name, @line)
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
    def extract_routes_from(root : LibTreeSitter::TSNode, source : String) : Array(Route)
      routes = [] of Route
      constants = extract_string_constants_from(root, source)
      walk_classes(root, source, [""], routes, constants)
      routes
    end

    def extract_string_constants_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      constants = Hash(String, String).new
      collect_string_constants(root, source, package_name(root, source), [] of String, constants)
      constants
    end

    # ---- private helpers ----------------------------------------------

    # Walk every class/interface declaration (including nested). Interfaces
    # are relevant for Spring Cloud Feign (`@FeignClient` + method
    # `@*Mapping` annotations). `outer_prefix` is the path prefix
    # accumulated from enclosing scopes.
    private def walk_classes(node : LibTreeSitter::TSNode,
                             source : String,
                             outer_prefixes : Array(String),
                             routes : Array(Route),
                             constants : Hash(String, String))
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration"
        class_name = class_simple_name(node, source)
        class_prefixes = class_mapping_prefixes(node, source, constants, class_name)
        class_prefixes = [""] if class_prefixes.empty?
        prefixes = [] of String
        outer_prefixes.each do |outer_prefix|
          class_prefixes.each do |class_prefix|
            prefixes << join_paths(outer_prefix, class_prefix)
          end
        end

        if body = Noir::TreeSitter.field(node, "body")
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "method_declaration"
              collect_method_routes(member, source, class_name, prefixes, routes, constants)
            when "class_declaration", "interface_declaration"
              walk_classes(member, source, prefixes, routes, constants)
            end
          end
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_classes(child, source, outer_prefixes, routes, constants)
      end
    end

    private def class_simple_name(class_decl : LibTreeSitter::TSNode, source : String) : String
      if name_node = Noir::TreeSitter.field(class_decl, "name")
        return Noir::TreeSitter.node_text(name_node, source)
      end
      ""
    end

    # Pull class-level `@RequestMapping(...)` / `@GetMapping(...)`
    # path contributions. Spring treats `value` / `path` as `String[]`,
    # so class-level arrays fan out across every method-level mapping.
    private def class_mapping_prefixes(class_decl : LibTreeSitter::TSNode,
                                       source : String,
                                       constants : Hash(String, String),
                                       class_name : String) : Array(String)
      each_annotation(class_decl, source) do |name, args_node|
        next unless ANNOTATION_VERBS.has_key?(name)
        paths = annotation_paths(args_node, source, constants, class_name)
        return paths unless paths.empty?
        return [] of String if annotation_has_path_argument?(args_node, source)
      end
      [] of String
    end

    private def collect_method_routes(method : LibTreeSitter::TSNode,
                                      source : String,
                                      class_name : String,
                                      class_prefixes : Array(String),
                                      routes : Array(Route),
                                      constants : Hash(String, String))
      method_name = ""
      if name_node = Noir::TreeSitter.field(method, "name")
        method_name = Noir::TreeSitter.node_text(name_node, source)
      end

      each_annotation(method, source) do |ann_name, args_node, ann_line|
        verb_default = ANNOTATION_VERBS[ann_name]?
        next unless ANNOTATION_VERBS.has_key?(ann_name)

        paths = annotation_paths(args_node, source, constants, class_name)
        next if paths.empty? && annotation_has_path_argument?(args_node, source)
        paths = [""] if paths.empty?

        verbs =
          if verb_default
            [verb_default]
          else
            methods = annotation_methods(args_node, source)
            methods.empty? ? ["GET"] : methods
          end

        # Fan out into every (path × verb) combination. Spring's
        # `@RequestMapping({"/a", "/b"}, method = {GET, POST})` emits
        # four routes.
        paths.each do |path|
          class_prefixes.each do |class_prefix|
            full = join_paths(class_prefix, path)
            verbs.each do |verb|
              routes << Route.new(verb, full, class_name, method_name, ann_line)
            end
          end
        end
      end
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
    #   - `value = "..."` / `path = "..."` keyword forms of either
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
          next unless k == "value" || k == "path"
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
          return true if k == "value" || k == "path"
        end
      end

      false
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
                                         constants : Hash(String, String))
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration" || ty == "enum_declaration" || ty == "annotation_type_declaration"
        name = class_simple_name(node, source)
        next_stack = name.empty? ? class_stack : class_stack + [name]
        Noir::TreeSitter.each_named_child(node) do |child|
          collect_string_constants(child, source, package_name, next_stack, constants)
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
        collect_string_constants(child, source, package_name, class_stack, constants)
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
    # `@GetMapping("")`) emits `prefix/` — matches Spring's runtime
    # behaviour and the legacy analyzer's `File.join("/prefix", "")`
    # trailing-slash convention.
    private def join_paths(prefix : String, path : String) : String
      return path if prefix.empty?
      return "#{prefix.rstrip('/')}/" if path.empty?
      trimmed_prefix = prefix.rstrip('/')
      trimmed_path = path.lstrip('/')
      "#{trimmed_prefix}/#{trimmed_path}"
    end
  end
end
