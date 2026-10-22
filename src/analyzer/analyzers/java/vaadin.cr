require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_type_model_extractor_ts"
require "../../../utils/url_path"
require "../../../detector/detectors/java/vaadin"

module Analyzer::Java
  # Vaadin Flow navigation targets (`@Route` / `@RouteAlias`, prefixed by
  # `@RoutePrefix` on the parent layouts) and Hilla browser-callable
  # services (`@BrowserCallable` / `@Endpoint`), which expose every public
  # method as `POST <prefix>/<Service>/<method>`.
  class Vaadin < Analyzer
    analyzer_for "java_vaadin"

    include JavaEngine

    alias Model = Noir::TreeSitterJavaTypeModel

    TAGGER         = "vaadin_analyzer"
    VAADIN_GATE    = Regex.union("com.vaadin", "dev.hilla")
    FLOW_ROUTER_RE = Regex.union("com.vaadin.flow.router")
    # `@Endpoint` is also Spring Boot Actuator's; only Hilla's counts.
    HILLA_RE          = Detector::Java::Vaadin::HILLA_MARKERS
    ROUTE_TEMPLATE_RE = /:([A-Za-z_]\w*)(?:\([^)]*\))?[?*]?/
    MAX_LAYOUT_DEPTH  = 8

    # Hilla's generic services: what a `@BrowserCallable` subclass inherits.
    LIST_SERVICE_METHODS = {"list" => %w[pageable filter], "get" => %w[id], "exists" => %w[id], "count" => %w[filter]}
    CRUD_SERVICE_METHODS = LIST_SERVICE_METHODS.merge({"save" => %w[value], "saveAll" => %w[values], "delete" => %w[id], "deleteAll" => %w[ids]})
    SERVICE_BASES        = {
      "ListRepositoryService" => LIST_SERVICE_METHODS,
      "ListService"           => LIST_SERVICE_METHODS,
      "CrudRepositoryService" => CRUD_SERVICE_METHODS,
      "CrudService"           => CRUD_SERVICE_METHODS,
    }

    private record Layout, prefix : String?, absolute : Bool, parent : String?

    def analyze
      files = [] of Tuple(String, String, Array(Model::TypeDecl))
      layouts = Hash(String, Layout).new
      get_files_by_extension(".java").each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        isolating_file_errors(path) do
          content = read_file_content(path)
          next unless content_matches?(content, VAADIN_GATE)

          types = Model.extract(content)
          types.each do |decl|
            prefix = decl.annotation("RoutePrefix")
            parent = decl.annotation("ParentLayout").try(&.string).try { |name| Model.simple_type_name(name) }
            next unless prefix || parent
            layouts[decl.name] ||= Layout.new(prefix.try(&.string), prefix.try(&.string("absolute")) == "true", parent)
          end
          files << {path, content, types}
        end
      end

      configs = Hash(String, Hash(String, String)).new
      files.each do |path, content, types|
        isolating_file_errors(path) do
          root = project_root_for(path)
          config = configs[root] ||= spring_config_values_for(root)
          context = normalize_optional_path(config["server.servlet.context-path"]?)
          flow = content_matches?(content, FLOW_ROUTER_RE)
          hilla = content_matches?(content, HILLA_RE)

          types.each do |decl|
            next unless decl.kind == "class"
            emit_flow_routes(path, decl, layouts, flow_base(context, config)) if flow
            if hilla && (service = decl.annotation("BrowserCallable") || decl.annotation("Endpoint"))
              emit_hilla_methods(path, decl, service, hilla_prefix(context, config))
            end
          end
        end
      end

      @result
    end

    private def flow_base(context : String, config : Hash(String, String)) : String
      mapping = config["vaadin.url-mapping"]? || config["vaadin.urlMapping"]? || ""
      Noir::URLPath.join_absorbing(context, normalize_optional_path(mapping.rchop("/*").rchop("*")))
    end

    private def hilla_prefix(context : String, config : Hash(String, String)) : String
      prefix = config["vaadin.endpoint.prefix"]? || config["hilla.endpoint.prefix"]? || "/connect"
      Noir::URLPath.join_absorbing(context, normalize_optional_path(prefix))
    end

    private def emit_flow_routes(path : String, decl : Model::TypeDecl, layouts : Hash(String, Layout), base : String)
      targets = decl.annotations.select { |ann| ann.name == "Route" || ann.name == "RouteAlias" }
      return if targets.empty?

      url_parameter = decl.supertypes.any? { |type| Model.simple_type_name(type) == "HasUrlParameter" }
      tag = access_tag(decl.annotations)
      targets.each do |ann|
        # A value that is a constant from another file: no route to report.
        next if ann.values.has_key?("value") && ann.string.nil?
        route = ann.string || (ann.name == "Route" ? derived_route(decl.name) : "")
        segments = ann.string("absolute") == "true" ? [] of String : layout_prefixes(ann.string("layout").try { |name| Model.simple_type_name(name) }, layouts)
        segments << route.gsub(ROUTE_TEMPLATE_RE) { "{#{$~[1]}}" }
        segments << "{parameter}" if url_parameter
        url = segments.reduce(base) { |acc, segment| Noir::URLPath.join_absorbing(acc, segment) }
        add(Noir::URLPath.join_rooted("", url), "GET", ann.line + 1, path, [] of Param, tag)
      end
    end

    private def emit_hilla_methods(path : String, decl : Model::TypeDecl, service : Model::Annotation, prefix : String)
      name = service.string || decl.name
      class_tag = access_tag(decl.annotations)
      decl.methods.each do |method|
        next unless method.modifiers.includes?("public")
        next if method.modifiers.includes?("static")

        params = method.params.map { |param| Param.new(param.name, "", "json") }
        url = Noir::URLPath.join_rooted(prefix, "#{name}/#{method.name}")
        add(url, "POST", method.line + 1, path, params, access_tag(method.annotations) || class_tag)
      end

      declared = decl.methods.map(&.name).to_set
      decl.supertypes.each do |type|
        next unless inherited = SERVICE_BASES[Model.simple_type_name(type)]?
        inherited.each do |method, args|
          next if declared.includes?(method)
          url = Noir::URLPath.join_rooted(prefix, "#{name}/#{method}")
          add(url, "POST", decl.line + 1, path, args.map { |arg| Param.new(arg, "", "json") }, class_tag)
        end
      end
    end

    # `@RoutePrefix` values of the `layout` chain, outermost first. A
    # prefix marked `absolute` cuts off everything above it.
    private def layout_prefixes(layout : String?, layouts : Hash(String, Layout)) : Array(String)
      prefixes = [] of String
      depth = 0
      while layout && depth < MAX_LAYOUT_DEPTH && (entry = layouts[layout]?)
        if prefix = entry.prefix
          prefixes.unshift(prefix)
          break if entry.absolute
        end
        layout = entry.parent
        depth += 1
      end
      prefixes
    end

    # `@Route` without a value: the class name minus a `View` suffix,
    # lower-cased; `Main` / `MainView` is the root.
    private def derived_route(class_name : String) : String
      return "" if class_name == "Main" || class_name == "MainView"
      name = class_name.ends_with?("View") && class_name.size > 4 ? class_name.rchop("View") : class_name
      name.downcase
    end

    private def access_tag(annotations : Array(Model::Annotation)) : Tag?
      annotations.each do |ann|
        case ann.name
        when "AnonymousAllowed"
          return Tag.new("anonymous", "Vaadin @AnonymousAllowed: reachable without login", TAGGER)
        when "PermitAll"
          return Tag.new("auth", "Protected by @PermitAll (any authenticated user)", TAGGER)
        when "RolesAllowed"
          return Tag.new("auth", "Protected by @RolesAllowed(#{ann.strings.join(", ")})", TAGGER)
        when "DenyAll"
          return Tag.new("auth", "Denied by @DenyAll", TAGGER)
        end
      end
      nil
    end

    private def add(url : String, verb : String, line : Int32, path : String, params : Array(Param), tag : Tag?)
      endpoint = Endpoint.new(url, verb, params, Details.new(PathInfo.new(path, line)))
      endpoint.add_tag(tag) if tag
      @result << endpoint
    end
  end
end
