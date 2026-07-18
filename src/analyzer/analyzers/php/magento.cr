require "../../engines/php_engine"
require "xml"

module Analyzer::Php
  # Magento 2 attack-surface extractor.
  #
  # Magento exposes two distinct HTTP surfaces:
  #
  #   * Web API (REST) — declared in `etc/webapi.xml`:
  #       <route url="/V1/products/:sku" method="GET"> ... </route>
  #     served under the `/rest` prefix -> `/rest/V1/products/{sku}`.
  #
  #   * MVC controllers — a module's `etc/{area}/routes.xml` binds a
  #     module to a URL `frontName`, and each `Controller/.../Action.php`
  #     class (with an `execute()` method) maps to
  #     `/{frontName}/{controller}/{action}`.
  #
  # We parse only `webapi.xml` / `routes.xml` (a Magento tree is full of
  # other XML — `module.xml`, `di.xml`, `config.xml`, `acl.xml` …) and
  # controller classes under `/Controller/`.
  class Magento < PhpEngine
    # `Http{Verb}ActionInterface` markers a controller can implement to
    # declare the HTTP methods it accepts.
    HTTP_ACTION_INTERFACES = {
      "HttpGetActionInterface"    => "GET",
      "HttpPostActionInterface"   => "POST",
      "HttpPutActionInterface"    => "PUT",
      "HttpDeleteActionInterface" => "DELETE",
      "HttpPatchActionInterface"  => "PATCH",
    }

    # module_name + area -> frontName, built from routes.xml before the
    # parallel controller pass and read-only thereafter.
    @front_names = {} of String => String

    # Magento route configs live in XML alongside PHP controllers.
    protected def php_source_files : Array(String)
      get_files_by_extension(".php") + get_files_by_extension(".xml")
    end

    def analyze
      @front_names = build_front_name_map
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    def analyze_file(path : String) : Array(Endpoint)
      base = File.basename(path)

      if base == "webapi.xml"
        analyze_webapi(path)
      elsif path.ends_with?(".php") && path.includes?("/Controller/")
        analyze_controller(path)
      else
        [] of Endpoint
      end
    end

    # -- routes.xml -> frontName map ------------------------------------

    private def build_front_name_map : Hash(String, String)
      map = {} of String => String

      get_files_by_extension(".xml").each do |path|
        next unless File.basename(path) == "routes.xml"
        next if PhpEngine.test_path?(path)

        area = area_for_routes_path(path)
        begin
          doc = XML.parse(read_file_content(path))
          root = doc.root
          next unless root

          each_descendant(root, "route") do |route_node|
            front_name = xml_attr(route_node, "frontName")
            next if front_name.empty?
            each_child(route_node, "module") do |module_node|
              module_name = xml_attr(module_node, "name")
              next if module_name.empty?
              map[route_key(module_name, area)] = front_name
            end
          end
        rescue e
          logger.debug "Error parsing Magento routes.xml #{path}: #{e}"
        end
      end

      map
    end

    private def area_for_routes_path(path : String) : String
      return "adminhtml" if path.includes?("/adminhtml/")
      "frontend"
    end

    private def route_key(module_name : String, area : String) : String
      "#{module_name} #{area}"
    end

    # -- webapi.xml (REST) ----------------------------------------------

    private def analyze_webapi(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      begin
        doc = XML.parse(read_file_content(path))
        root = doc.root
        return endpoints unless root

        each_descendant(root, "route") do |route_node|
          url = xml_attr(route_node, "url")
          next if url.empty?
          method = xml_attr(route_node, "method")
          method = "GET" if method.empty?

          full_path = build_rest_path(url)
          params = extract_brace_path_params(full_path)
          endpoints << Endpoint.new(full_path, method.upcase, params, details.dup)
        end
      rescue e
        logger.debug "Error parsing Magento webapi.xml #{path}: #{e}"
      end

      endpoints
    end

    # `/rest` + webapi url, `:sku` path segments rewritten to `{sku}`.
    private def build_rest_path(url : String) : String
      normalized = normalize_colon_params(url)
      combined = "/rest/#{normalized.strip.lstrip('/')}"
      combined = combined.gsub(/\/+/, "/")
      combined.size > 1 ? combined.chomp('/') : combined
    end

    private def normalize_colon_params(url : String) : String
      url.gsub(/:([A-Za-z_]\w*)/) { "{#{$1}}" }
    end

    # -- MVC controllers ------------------------------------------------

    private def analyze_controller(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      content = read_file_content(path)
      # A real action controller has an execute() method. Anchor the match
      # so `executeInternal()` / `executeAny()` helpers don't slip through,
      # and skip abstract base classes under /Controller/.
      return endpoints unless content.matches?(/\bfunction\s+execute\s*\(/)
      return endpoints if content.includes?("abstract class")

      url = controller_route_target(path)
      return endpoints unless url

      methods = extract_controller_methods(content)
      details = Details.new(PathInfo.new(path))

      methods.each do |method|
        endpoints << Endpoint.new(url, method, [] of Param, details.dup)
      end

      endpoints
    end

    # Resolve `/{frontName}/{controller}/{action}` from the controller's
    # module (path-derived) and the routes.xml frontName map. Returns nil
    # when the module has no registered frontName (unresolvable route).
    private def controller_route_target(path : String) : String?
      parts = path.split("/").reject(&.empty?)
      # Use the LAST `Controller` segment: the module's controller root is
      # `.../Vendor/Module/Controller/...`, and an ancestor directory in the
      # scan path could also be literally named "Controller".
      ctrl_index = parts.rindex("Controller")
      return unless ctrl_index && ctrl_index >= 2

      vendor = parts[ctrl_index - 2]
      module_name = parts[ctrl_index - 1]
      full_module = "#{vendor}_#{module_name}"

      rest = parts[(ctrl_index + 1)..]
      return if rest.empty?

      area = "frontend"
      if rest.first == "Adminhtml"
        area = "adminhtml"
        rest = rest[1..]
        return if rest.empty?
      end

      front_name = @front_names[route_key(full_module, area)]?
      return unless front_name

      # Last segment is the action file; the preceding directory segments
      # form ONE URL controller segment joined by '_' (Magento's Base
      # router collapses nested Controller/ subdirs into a single segment:
      # Controller/Order/Creditmemo/Save.php -> {frontName}/order_creditmemo/save).
      action = File.basename(rest.last, ".php").downcase
      controller_segment = rest[0...-1].map(&.downcase).join("_")

      segments = [front_name.downcase]
      segments << controller_segment unless controller_segment.empty?
      segments << action
      "/" + segments.join("/")
    end

    private def extract_controller_methods(content : String) : Array(String)
      methods = [] of String
      # Only interfaces in the class's `implements` clause count — a bare
      # `use ...\HttpPostActionInterface;` import or a docblock mention must
      # not add a verb the controller does not actually accept.
      implements = extract_implements_clause(content)
      HTTP_ACTION_INTERFACES.each do |interface, verb|
        methods << verb if implements.includes?(interface)
      end
      # Legacy controllers (extends \Magento\Framework\App\Action\Action)
      # declare no interface and accept any verb; default to GET.
      methods << "GET" if methods.empty?
      methods.uniq
    end

    # The `implements ...` list of the first class declaration, or "" when
    # the class implements nothing (legacy `extends Action` controllers).
    private def extract_implements_clause(content : String) : String
      m = content.match(/\bclass\s+\w+[^{]*?\bimplements\b([^{]*)\{/m)
      m ? m[1] : ""
    end

    # -- XML helpers ----------------------------------------------------

    private def xml_attr(node : XML::Node, name : String) : String
      node[name]?.try(&.strip) || ""
    end

    private def each_child(node : XML::Node, local_name : String, &)
      node.children.each do |child|
        yield child if child.element? && child.name == local_name
      end
    end

    # Depth-first walk yielding every descendant element with the given
    # local name (namespace-agnostic).
    private def each_descendant(node : XML::Node, local_name : String, &block : XML::Node ->)
      node.children.each do |child|
        next unless child.element?
        block.call(child) if child.name == local_name
        each_descendant(child, local_name, &block)
      end
    end
  end
end
