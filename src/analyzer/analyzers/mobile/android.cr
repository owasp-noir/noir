require "xml"
require "../../../models/analyzer"

module Analyzer::Mobile
  # Parses AndroidManifest.xml to surface mobile app entry points:
  #   * custom URL scheme deep links (intent-filter > data android:scheme)
  #   * verified App Links (autoVerify intent-filter on http/https)
  #   * exported components with a data-less action filter (IPC surface)
  #
  # One endpoint is emitted per deep-link URI; the handling component lives
  # in `metadata["via"]`, not a separate entry. A bare `intent://component`
  # endpoint is emitted only for exported components whose filter declares
  # an action but no <data> URI (and isn't the launcher).
  #
  # All endpoints keep method = "GET"; the mobile semantics live in
  # `protocol` (mobile-scheme / universal-link / android-intent). `@string/`
  # values are resolved against res/values/strings.xml when present.
  class Android < Analyzer
    LAUNCHER_ACTION = "android.intent.action.MAIN"

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

        if !data_nodes.empty?
          # Deep-link / app-link URI(s) — the primary entry points. The
          # handling component rides along as metadata["via"].
          data_nodes.each do |data|
            emit_data_endpoint(data, actions, categories, package, strings,
              path, auto_verify, component_name, seen_urls)
          end
        elsif exported
          # Exported component with an action but no <data>: an IPC surface
          # reachable by explicit/implicit intent. The launcher (MAIN) is
          # an app start, not a remote surface, so it's excluded.
          ipc_actions = actions.reject { |a| a == LAUNCHER_ACTION }
          unless ipc_actions.empty?
            emit_intent_endpoint(component_name, ipc_actions, categories,
              package, path, seen_urls)
          end
        end
      end
    end

    # Emits a mobile-scheme (custom scheme) or universal-link (verified
    # http/https) endpoint for one <data> node.
    private def emit_data_endpoint(data : XML::Node, actions : Array(String),
                                   categories : Array(String), package : String,
                                   strings : Hash(String, String), path : String,
                                   auto_verify : Bool, via : String, seen_urls : Set(String))
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
      endpoint.metadata = build_metadata(via, actions, categories, host, package)

      mark_unresolved(endpoint, url)
      @result << endpoint
    end

    # Emits an android-intent endpoint for an exported, data-less component,
    # using the synthetic intent:// scheme so the optimizer leaves the URL
    # untouched.
    private def emit_intent_endpoint(component_name : String, actions : Array(String),
                                     categories : Array(String), package : String,
                                     path : String, seen_urls : Set(String))
      component = component_name.empty? ? package : "#{package}/#{component_name}"
      url = "intent://#{component}"
      return unless seen_urls.add?(url)

      endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
      endpoint.protocol = "android-intent"
      endpoint.metadata = build_metadata("", actions, categories, "", package)

      @result << endpoint
    end

    private def build_metadata(via : String, actions : Array(String),
                               categories : Array(String), host : String,
                               package : String) : Hash(String, String)
      metadata = {} of String => String
      metadata["via"] = via unless via.empty?
      metadata["action"] = actions.first if actions.size > 0
      metadata["category"] = categories.first if categories.size > 0
      metadata["host"] = host unless host.empty?
      metadata["package"] = package unless package.empty?
      metadata
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

    ANDROID_NS = "http://schemas.android.com/apk/res/android"

    # Reads an attribute by local name (libxml2 exposes the prefixed name).
    # Prefers the `android:`-namespaced attribute so a `tools:`/other-prefix
    # `scheme`/`host`/`exported` in the same tag can't shadow the real value;
    # falls back to a non-namespaced match (e.g. `package` on <manifest>).
    private def attr(node : XML::Node, local_name : String) : String?
      fallback : String? = nil
      node.attributes.each do |a|
        next unless a.name == local_name
        return a.content if a.namespace.try(&.href) == ANDROID_NS
        fallback ||= a.content
      end
      fallback
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
