require "xml"
require "yaml"
require "../ext/tree_sitter/tree_sitter"
require "../utils/url_path"
require "../utils/xml_comments"
require "./java_route_extractor_ts"

module Noir
  # Apache Camel HTTP entry points, from the three route-definition
  # languages Camel reads: the Java DSL (`RouteBuilder#configure`), the XML
  # DSL and the YAML DSL. Two shapes, in each language:
  #
  #   * REST DSL: `rest("/users").get("/{id}").post()...` — paths are
  #     relative to `restConfiguration().contextPath(...)`, which the
  #     caller applies (it is CamelContext-wide, so usually in another file).
  #   * HTTP consumers: `from("platform-http:/x")`, `from("jetty:http://h/x")`,
  #     `from("servlet:/x")`, ... and the REST component `from("rest:get:/x")`.
  #
  # No file I/O; one `FileResult` per source.
  module CamelRouteExtractor
    extend self

    VERBS = Set{"get", "post", "put", "patch", "delete", "head"}

    # Content gates for route files, shared by the detector and the analyzer.
    JAVA_DSL = "org.apache.camel"
    XML_DSL  = /camel\.apache\.org\/schema|<camel[\s>]/
    # `/m`: in Crystal, `^` matches only at the start of the string without it.
    YAML_DSL = /^-[ \t]+(?:rest|route|from|restConfiguration|rest-configuration):/m

    # Camel `RestParamType` -> noir param type.
    PARAM_TYPES = {"path" => "path", "query" => "query", "header" => "header", "body" => "json", "formData" => "form"}

    CONSUMER_URI     = /\A(platform-http|servlet|jetty|netty-http|undertow|rest):(.*)\z/
    URI_HOST         = %r{\Ahttps?://[^/]*}
    METHOD_RESTRICT  = /(?:\A|&)httpMethodRestrict=([^&]*)/
    YAML_CONTEXT_KEY = Set{"restConfiguration", "rest-configuration"}

    # A declared param's noir type; Camel's `RestParamType` defaults to path.
    def param_type(raw : String?) : String
      PARAM_TYPES[raw || "path"]? || "query"
    end

    class Route
      getter verb : String
      getter path : String
      # 0-based source line.
      getter line : Int32
      # REST DSL / `rest:` routes sit under `restConfiguration().contextPath`.
      getter? rest : Bool
      getter params = [] of Tuple(String, String)
      property body_type : String? = nil

      def initialize(@verb, @path, @line, @rest)
      end
    end

    record FileResult, routes : Array(Route), context_path : String?

    # Endpoints of one consumer URI. Non-HTTP components yield none.
    def consumer_routes(uri : String, line : Int32, method_restrict : String? = nil) : Array(Route)
      return [] of Route unless match = uri.strip.match(CONSUMER_URI)
      target, _, query = match[2].lchop("//").partition('?')

      if match[1] == "rest"
        # `rest:get:hello:{me}` = method, path, optional uri template.
        verb, _, path = target.partition(':')
        return [] of Route unless VERBS.includes?(verb.downcase)
        path, _, template = path.partition(':')
        return [Route.new(verb.upcase, URLPath.absolute_join(path, template), line, true)]
      end

      path = URLPath.absolute_join(target.sub(URI_HOST, ""))
      restrict = method_restrict || query.match(METHOD_RESTRICT).try(&.[1])
      verbs = restrict.try(&.split(',').map(&.strip.upcase).reject(&.empty?)) || [] of String
      verbs = ["ANY"] if verbs.empty?
      verbs.map { |verb| Route.new(verb, path, line, false) }
    end

    # ---- Java DSL ------------------------------------------------------

    def extract_java(source : String) : FileResult
      walker = JavaWalker.new(source)
      Noir::TreeSitter.parse_java(source) do |root|
        walker.constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
        walker.walk(root)
      end
      FileResult.new(walker.routes, walker.context_path)
    end

    private class JavaWalker
      alias Node = LibTreeSitter::TSNode

      getter routes = [] of Route
      getter context_path : String? = nil
      property constants = Hash(String, String).new

      def initialize(@source : String)
      end

      # Each call chain is handled once, at its outermost link; only the
      # links' argument lists are descended into, so a long chain is linear.
      def walk(node : Node)
        unless Noir::TreeSitter.node_type(node) == "method_invocation"
          Noir::TreeSitter.each_named_child(node) { |child| walk(child) }
          return
        end

        links = [node]
        while (receiver = Noir::TreeSitter.field(links.last, "object")) && Noir::TreeSitter.node_type(receiver) == "method_invocation"
          links << receiver
        end
        links.reverse!
        handle_chain(links)
        Noir::TreeSitter.field(links.first, "object").try { |head_receiver| walk(head_receiver) }
        links.each { |link| Noir::TreeSitter.field(link, "arguments").try { |args| walk(args) } }
      end

      private def handle_chain(links : Array(Node))
        head = links.first
        object = Noir::TreeSitter.field(head, "object")
        return if object && Noir::TreeSitter.node_text(object, @source) != "this"

        case name(head)
        when "rest"
          rest_chain(links)
        when "restConfiguration"
          links.each do |link|
            @context_path ||= string_arg(link) if name(link) == "contextPath"
          end
        when "from"
          if uri = string_arg(head)
            @routes.concat(CamelRouteExtractor.consumer_routes(uri, Noir::TreeSitter.call_name_row(head)))
          end
        end
      end

      # `rest(base).get(path?)...type(User.class)...param().name(n).type(RestParamType.query).endParam()...`
      #
      # A base or verb path that does not resolve to a string (a constant
      # from another file, a field, a parameter) drops its routes rather
      # than reporting them under a wrong URL.
      private def rest_chain(links : Array(Node))
        base = "".as(String?)
        current = nil.as(Route?)
        param_name = nil.as(String?)
        param_type = "path"
        in_param = false

        links.each do |link|
          method = name(link)
          if in_param && (method == "endParam" || VERBS.includes?(method) || method == "rest")
            add_param(current, param_name, param_type)
            in_param = false
          end

          case method
          when "rest", "path"
            base = path_arg(link) if method == "rest" || current.nil?
            current = nil if method == "rest"
          when .in?(VERBS)
            path = path_arg(link)
            current = base && path ? Route.new(method.upcase, URLPath.absolute_join(base, path), Noir::TreeSitter.call_name_row(link), true) : nil
            current.try { |route| @routes << route }
          when "param"
            next unless current
            in_param = true
            param_name = nil
            param_type = "path"
          when "name"
            param_name = string_arg(link) if in_param
          when "type"
            next unless current && (arg = first_arg(link))
            text = Noir::TreeSitter.node_text(arg, @source)
            if in_param
              param_type = text.split('.').last
            elsif Noir::TreeSitter.node_type(arg) == "class_literal"
              current.body_type = text.chomp(".class").split('.').last
            end
          end
        end
        add_param(current, param_name, param_type) if in_param
      end

      private def add_param(route : Route?, name : String?, type : String)
        route.params << {name, CamelRouteExtractor.param_type(type)} if route && name
      end

      private def name(call : Node) : String
        Noir::TreeSitter.field(call, "name").try { |node| Noir::TreeSitter.node_text(node, @source) } || ""
      end

      private def first_arg(call : Node) : Node?
        Noir::TreeSitter.field(call, "arguments").try { |args| Noir::TreeSitter.first_named_child(args) }
      end

      # "" for a call with no arguments, nil for an unresolvable one.
      private def path_arg(call : Node) : String?
        first_arg(call) ? string_arg(call) : ""
      end

      private def string_arg(call : Node) : String?
        return unless arg = first_arg(call)
        case Noir::TreeSitter.node_type(arg)
        when "string_literal"
          Noir::TreeSitter.decode_string_literal(arg, @source)
        when "identifier", "field_access"
          text = Noir::TreeSitter.node_text(arg, @source)
          suffix = ".#{text}"
          @constants[text]? || @constants.find { |key, _| key.ends_with?(suffix) }.try(&.[1])
        end
      end
    end

    # ---- XML DSL -------------------------------------------------------

    def extract_xml(content : String) : FileResult
      routes = [] of Route
      context_path = nil.as(String?)
      each_element(Noir::XmlComments.parse(content)) do |node|
        case node.name
        when "restConfiguration"
          context_path ||= node["contextPath"]?
        when "rest"
          base = node["path"]? || node["uri"]? || ""
          node.children.each do |verb|
            next unless verb.element? && VERBS.includes?(verb.name)
            route = Route.new(verb.name.upcase, URLPath.absolute_join(base, verb["path"]? || verb["uri"]? || ""), xml_row(verb), true)
            route.body_type = verb["type"]?.try(&.split('.').last)
            verb.children.each do |param|
              next unless param.element? && param.name == "param" && (param_name = param["name"]?)
              route.params << {param_name, param_type(param["type"]?)}
            end
            routes << route
          end
        when "from"
          node["uri"]?.try { |uri| routes.concat(consumer_routes(uri, xml_row(node))) }
        end
      end
      FileResult.new(routes, context_path)
    end

    # 0-based line of an element. ponytail: libxml2 stores it in a UInt16,
    # so it saturates past line 65535.
    private def xml_row(node : XML::Node) : Int32
      node.to_unsafe.value.line.to_i - 1
    end

    private def each_element(node : XML::Node, &block : XML::Node ->)
      node.children.each do |child|
        next unless child.element?
        block.call(child)
        each_element(child, &block)
      end
    end

    # ---- YAML DSL ------------------------------------------------------

    def extract_yaml(content : String) : FileResult
      routes = [] of Route
      context_path = nil.as(String?)
      items = YAML::Nodes.parse_all(content).flat_map do |doc|
        top = doc.nodes.first?
        top.is_a?(YAML::Nodes::Sequence) ? top.nodes : [] of YAML::Nodes::Node
      end

      items.each do |item|
        each_pair(item) do |key, value|
          case key
          when "rest"
            yaml_rest(value, routes)
          when "route"
            yaml_from(yaml_get(value, "from"), routes)
          when "from"
            yaml_from(value, routes)
          when .in?(YAML_CONTEXT_KEY)
            context_path ||= scalar(yaml_get(value, "contextPath") || yaml_get(value, "context-path"))
          end
        end
      end
      FileResult.new(routes, context_path)
    end

    private def yaml_rest(rest : YAML::Nodes::Node, routes : Array(Route))
      base = scalar(yaml_get(rest, "path") || yaml_get(rest, "uri")) || ""
      each_pair(rest) do |key, value|
        next unless VERBS.includes?(key)
        verbs = value.is_a?(YAML::Nodes::Sequence) ? value.nodes : [value]
        verbs.each do |verb|
          route = Route.new(key.upcase, URLPath.absolute_join(base, scalar(yaml_get(verb, "path") || yaml_get(verb, "uri")) || ""), verb.start_line - 1, true)
          route.body_type = scalar(yaml_get(verb, "type")).try(&.split('.').last)
          params = yaml_get(verb, "param")
          if params.is_a?(YAML::Nodes::Sequence)
            params.nodes.each do |param|
              next unless param_name = scalar(yaml_get(param, "name"))
              route.params << {param_name, param_type(scalar(yaml_get(param, "type")))}
            end
          end
          routes << route
        end
      end
    end

    private def yaml_from(from : YAML::Nodes::Node?, routes : Array(Route))
      return unless from && (uri_node = yaml_get(from, "uri")) && (uri = scalar(uri_node))
      restrict = scalar(yaml_get(yaml_get(from, "parameters"), "httpMethodRestrict"))
      routes.concat(consumer_routes(uri, uri_node.start_line - 1, restrict))
    end

    private def each_pair(node : YAML::Nodes::Node?, &)
      return unless node.is_a?(YAML::Nodes::Mapping)
      node.nodes.each_slice(2) do |pair|
        key = pair[0]
        yield key.value, pair[1] if key.is_a?(YAML::Nodes::Scalar) && pair.size == 2
      end
    end

    private def yaml_get(node : YAML::Nodes::Node?, key : String) : YAML::Nodes::Node?
      each_pair(node) { |name, value| return value if name == key }
      nil
    end

    private def scalar(node : YAML::Nodes::Node?) : String?
      node.as?(YAML::Nodes::Scalar).try(&.value.presence)
    end
  end
end
