require "../../engines/specification_engine"

module Analyzer::Specification
  # Spring Cloud Gateway routes declared in Spring Boot config:
  # `spring.cloud.gateway[.server.webflux|.server.webmvc|.mvc].routes[]`, each
  # with `predicates` in shortcut (`Path=/a/**,/b`, `Method=GET,POST`) or
  # expanded (`name: Path`, `args: {patterns: [...]}`) form. A route without a
  # `Method` predicate matches every verb; one without a `Path` predicate is
  # not path-scoped and is skipped.
  class SpringCloudGateway < SpecificationEngine
    analyzer_for "spring_cloud_gateway"

    ROUTE_PREFIXES = [
      %w[spring cloud gateway routes],
      %w[spring cloud gateway server webflux routes],
      %w[spring cloud gateway server webmvc routes],
      %w[spring cloud gateway mvc routes],
    ]
    PROPERTY_RE   = /^\s*spring\.cloud\.gateway((?:\.server\.web(?:flux|mvc)|\.mvc)?\.routes\[\d+\])\.(\S+?)\s*[=:]\s*(.*?)\s*$/
    PREDICATE_KEY = /\Apredicates\[(\d+)\](?:\.(name|args)\b.*)?\z/
    # `- id: users`, for the line a route is declared on.
    ID_LINE = /^[ \t]*-[ \t]*id[ \t]*:[ \t]*["']?([^\s"'#]+)/m
    # Expanded-form args that are flags, not patterns.
    FLAG_ARGS = Set{"matchTrailingSlash", "matchOptionalTrailingSeparator"}

    private record Predicate, name : String, args : Array(String)
    private record Route, uri : String?, predicates : Array(Predicate), line : Int32? = nil

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::SPRING_CLOUD_GATEWAY_SPEC) do |path, details|
        content = read_file_content(path)
        routes = path.ends_with?(".properties") ? properties_routes(content) : yaml_routes(content)
        routes.each { |route| emit(route, details) }
      end

      @result
    end

    private def yaml_routes(content : String) : Array(Route)
      lines = value_lines(content, ID_LINE)
      routes = [] of Route
      YAML.parse_all(content).each do |doc|
        ROUTE_PREFIXES.each do |prefix|
          each_dotted(doc, prefix) do |node|
            list = node.as_a? || node.as_h?.try(&.values) || [] of YAML::Any
            list.each do |route|
              next unless route_h = route.as_h?
              predicates = (route_h[YAML::Any.new("predicates")]?.try(&.as_a?) || [] of YAML::Any).compact_map { |p| yaml_predicate(p) }
              id = route_h[YAML::Any.new("id")]?.try(&.to_s)
              routes << Route.new(route_h[YAML::Any.new("uri")]?.try(&.as_s?), predicates, id.try { |i| take_line(lines, i) })
            end
          end
        end
      end
      routes
    end

    # Spring binds `spring.cloud.gateway.routes` and a nested
    # `spring: {cloud: {gateway: {routes: ...}}}` alike, so a key may stand for
    # any run of the dotted segments.
    private def each_dotted(node : YAML::Any, segments : Array(String), &block : YAML::Any -> Nil) : Nil
      return block.call(node) if segments.empty?
      return unless hash = node.as_h?
      hash.each do |key, value|
        next unless parts = key.as_s?.try(&.split('.'))
        next unless parts.size <= segments.size && segments[0, parts.size] == parts
        each_dotted(value, segments[parts.size..], &block)
      end
    end

    private def yaml_predicate(node : YAML::Any) : Predicate?
      if text = node.as_s?
        shortcut_predicate(text)
      elsif hash = node.as_h?
        return unless name = hash[YAML::Any.new("name")]?.try(&.as_s?)
        args = [] of String
        if args_h = hash[YAML::Any.new("args")]?.try(&.as_h?)
          args_h.each do |key, value|
            next if FLAG_ARGS.includes?(key.as_s? || "")
            if values = value.as_a?
              values.each { |v| args << v.to_s }
            else
              args << value.to_s
            end
          end
        elsif args_a = hash[YAML::Any.new("args")]?.try(&.as_a?)
          args_a.each { |v| args << v.to_s }
        end
        Predicate.new(name, args)
      end
    end

    private def shortcut_predicate(text : String) : Predicate?
      name, sep, args = text.partition('=')
      return if sep.empty?
      name = name.strip
      values = args.split(',')
      # `Path=/a,/b,false`: a trailing boolean is the `matchTrailingSlash` flag.
      values.pop if name == "Path" && values.last.strip.downcase.in?("true", "false")
      Predicate.new(name, values)
    end

    private def properties_routes(content : String) : Array(Route)
      uris = {} of String => String
      lines = {} of String => Int32
      # route (prefix + index) => predicate index => {name, args}
      predicates = Hash(String, Hash(String, {String, Array(String)})).new
      content.each_line.with_index(1) do |line, number|
        next unless m = PROPERTY_RE.match(line)
        route, key, value = m[1], m[2], m[3]
        lines[route] ||= number
        if key == "uri"
          uris[route] = value
        elsif pm = PREDICATE_KEY.match(key)
          slots = predicates[route] ||= {} of String => {String, Array(String)}
          name, args = slots[pm[1]]? || {"", [] of String}
          case pm[2]?
          when "name" then name = value
          when "args" then args << value unless FLAG_ARGS.any? { |flag| key.ends_with?(flag) }
          else
            if shortcut = shortcut_predicate(value)
              name, args = shortcut.name, shortcut.args
            end
          end
          slots[pm[1]] = {name, args}
        end
      end

      predicates.map do |route, slots|
        list = slots.values.map { |name, args| Predicate.new(name, args) }
        Route.new(uris[route]?, list, lines[route]?)
      end
    end

    # Spring binds a comma-separated string to a list argument, in the shortcut
    # form (`Method=GET,POST`) and the expanded one (`methods: GET,POST`) alike.
    private def predicate_args(route : Route, name : String) : Array(String)
      route.predicates.select(&.name.==(name)).flat_map(&.args).flat_map(&.split(',')).map(&.strip).reject(&.empty?)
    end

    private def emit(route : Route, details : Details)
      paths = predicate_args(route, "Path")
      methods = predicate_args(route, "Method").map(&.upcase)
      methods = ["ANY"] if methods.empty?
      hosts = predicate_args(route, "Host")

      paths.each do |path|
        methods.each do |method|
          endpoint = Endpoint.new(path, method, details_at(details, route.line))
          # `add_tag` keeps one tag per name, so the hosts share one.
          endpoint.add_tag(Tag.new("spring-cloud-gateway-host", hosts.join(", "), "spring_cloud_gateway_analyzer")) unless hosts.empty?
          if uri = route.uri.presence
            endpoint.add_tag(Tag.new("spring-cloud-gateway-uri", uri, "spring_cloud_gateway_analyzer"))
          end
          @result << endpoint
        end
      end
    end
  end
end
