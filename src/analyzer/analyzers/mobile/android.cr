require "xml"
require "../../../models/analyzer"

module Analyzer::Mobile
  # Parses AndroidManifest.xml to surface mobile app entry points:
  #   * custom URL scheme deep links (intent-filter > data android:scheme)
  #   * exported intent components (activity/service/receiver with a filter)
  #   * App Links (autoVerify intent-filter on http/https)
  #
  # All endpoints keep method = "GET"; the mobile semantics live in
  # `protocol` (mobile-scheme / android-intent / universal-link) and the
  # `metadata` hash. `@string/foo` values are resolved against
  # res/values/strings.xml when present.
  class Android < Analyzer
    def analyze
      locator = CodeLocator.instance
      manifests = locator.all("android-manifest")
      return @result unless manifests.is_a?(Array(String))

      manifests.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          parse_manifest(content, path)
        rescue e
          @logger.debug "Failed to parse AndroidManifest #{path}: #{e.message}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def parse_manifest(content : String, path : String)
      doc = XML.parse(content)
      manifest = find_child(doc, "manifest")
      return unless manifest

      package = attr(manifest, "package") || ""
      strings = load_strings(path)

      application = find_child(manifest, "application")
      return unless application

      seen_urls = Set(String).new

      {"activity", "activity-alias", "service", "receiver"}.each do |component_tag|
        each_child(application, component_tag) do |component|
          process_component(component, package, strings, path, seen_urls)
        end
      end
    end

    private def process_component(component : XML::Node,
                                  package : String, strings : Hash(String, String),
                                  path : String, seen_urls : Set(String))
      exported = bool_attr(component, "exported")
      component_name = attr(component, "name") || ""

      filters = [] of XML::Node
      each_child(component, "intent-filter") { |f| filters << f }
      return if filters.empty?

      filters.each do |filter|
        actions = collect_names(filter, "action")
        categories = collect_names(filter, "category")
        data_nodes = [] of XML::Node
        each_child(filter, "data") { |d| data_nodes << d }
        auto_verify = bool_attr(filter, "autoVerify")

        # Deep-link / app-link endpoints from <data> entries.
        data_nodes.each do |data|
          emit_data_endpoints(data, actions, categories, package, strings,
            path, auto_verify, seen_urls)
        end

        # Exported intent component that handles a deep-link <data> intent —
        # the issue's INTENT entries. Plain MAIN/LAUNCHER components carry no
        # <data> and are intentionally excluded.
        if exported && !data_nodes.empty?
          emit_intent_endpoint(component_name, actions, categories, data_nodes,
            package, strings, path, seen_urls)
        end
      end
    end

    # Emits a mobile-scheme (custom scheme) or universal-link (http/https +
    # autoVerify) endpoint for one <data> node.
    private def emit_data_endpoints(data : XML::Node, actions : Array(String),
                                    categories : Array(String), package : String,
                                    strings : Hash(String, String), path : String,
                                    auto_verify : Bool, seen_urls : Set(String))
      scheme = resolve(attr(data, "scheme"), strings)
      return if scheme.nil? || scheme.empty?

      host = resolve(attr(data, "host"), strings) || ""
      norm_path = normalize_path(data, strings)
      web = scheme == "http" || scheme == "https"

      url = "#{scheme}://#{host}#{norm_path}"
      return unless seen_urls.add?(url)

      protocol = (web && auto_verify) ? "universal-link" : "mobile-scheme"
      endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
      endpoint.protocol = protocol

      metadata = {} of String => String
      metadata["type"] = protocol
      metadata["intent"] = actions.first if actions.size > 0
      metadata["category"] = categories.first if categories.size > 0
      metadata["host"] = host unless host.empty?
      metadata["package"] = package unless package.empty?
      endpoint.metadata = metadata

      mark_unresolved(endpoint, url)
      @result << endpoint
    end

    # Emits an android-intent endpoint for an exported component, using the
    # synthetic intent:// scheme so the optimizer leaves the URL untouched.
    private def emit_intent_endpoint(component_name : String, actions : Array(String),
                                     categories : Array(String), data_nodes : Array(XML::Node),
                                     package : String, strings : Hash(String, String),
                                     path : String, seen_urls : Set(String))
      component = component_name.empty? ? package : "#{package}/#{component_name}"
      url = "intent://#{component}"
      return unless seen_urls.add?(url)

      endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
      endpoint.protocol = "android-intent"

      metadata = {} of String => String
      metadata["type"] = "android-intent"
      metadata["action"] = actions.first if actions.size > 0
      metadata["category"] = categories.first if categories.size > 0
      if data_uri = data_uri_for(data_nodes, strings)
        metadata["data"] = data_uri
      end
      metadata["package"] = package unless package.empty?
      endpoint.metadata = metadata

      @result << endpoint
    end

    # Builds a representative data URI (scheme://host/path) for an intent's
    # <data> nodes so the INTENT entry can echo what it responds to.
    private def data_uri_for(data_nodes : Array(XML::Node), strings : Hash(String, String)) : String?
      data_nodes.each do |data|
        scheme = resolve(attr(data, "scheme"), strings)
        next if scheme.nil? || scheme.empty?
        host = resolve(attr(data, "host"), strings) || ""
        return "#{scheme}://#{host}#{normalize_path(data, strings)}"
      end
      nil
    end

    # Normalizes android:path / pathPrefix / pathPattern to a Noir-style
    # path. Templated `{id}` segments are rewritten to `:id` so the
    # optimizer's path-param pass picks them up.
    private def normalize_path(data : XML::Node, strings : Hash(String, String)) : String
      if path = resolve(attr(data, "path"), strings)
        return templatize(path)
      end
      if prefix = resolve(attr(data, "pathPrefix"), strings)
        return templatize(prefix)
      end
      if pattern = resolve(attr(data, "pathPattern"), strings)
        # Patterns are regex-ish (.* / .*foo); keep the literal prefix only.
        literal = pattern.split(/[.*\\]/).first
        return templatize(literal)
      end
      ""
    end

    private def templatize(path : String) : String
      path.gsub(/\{([^}]+)\}/, ":\\1")
    end

    private def mark_unresolved(endpoint : Endpoint, url : String)
      return unless url.includes?("@string/") || url.includes?("@{")
      endpoint.add_tag(Tag.new("unresolved", "Contains an unresolved manifest reference", "android"))
    end

    # Resolves @string/foo against res/values/strings.xml; leaves any other
    # value as-is and passes nil through.
    private def resolve(value : String?, strings : Hash(String, String)) : String?
      return value if value.nil?
      if value.starts_with?("@string/")
        key = value.lchop("@string/")
        return strings[key]? || value
      end
      value
    end

    # Loads <manifest_dir>/res/values/strings.xml into a name→value hash.
    # Returns an empty hash if the file is missing or unparsable.
    private def load_strings(manifest_path : String) : Hash(String, String)
      strings = {} of String => String
      strings_path = File.join(File.dirname(manifest_path), "res", "values", "strings.xml")
      return strings unless File.exists?(strings_path)

      begin
        content = read_file_content(strings_path)
        doc = XML.parse(content)
        if resources = find_child(doc, "resources")
          each_child(resources, "string") do |node|
            name = attr(node, "name")
            strings[name] = node.content if name
          end
        end
      rescue e
        @logger.debug "Failed to parse strings.xml #{strings_path}: #{e.message}"
      end

      strings
    end

    private def collect_names(parent : XML::Node, tag : String) : Array(String)
      names = [] of String
      each_child(parent, tag) do |node|
        if name = attr(node, "name")
          names << name
        end
      end
      names
    end

    private def bool_attr(node : XML::Node, local_name : String) : Bool
      attr(node, local_name) == "true"
    end

    # Reads an attribute by local name, ignoring the `android:` namespace
    # prefix (libxml2 exposes the prefixed name on the node).
    private def attr(node : XML::Node, local_name : String) : String?
      node.attributes.each do |a|
        return a.content if a.name == local_name
      end
      nil
    end

    private def find_child(node : XML::Node, local_name : String) : XML::Node?
      node.children.each do |c|
        return c if c.element? && c.name == local_name
      end
      nil
    end

    private def each_child(node : XML::Node, local_name : String, &)
      node.children.each do |c|
        yield c if c.element? && c.name == local_name
      end
    end
  end
end
