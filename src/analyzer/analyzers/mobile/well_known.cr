require "json"
require "../../../models/analyzer"

module Analyzer::Mobile
  # Parses the server-side half of a mobile universal-link association — the
  # well-known files a host publishes so the OS opens an app for its URLs:
  #
  #   * Android App Links   — /.well-known/assetlinks.json (Digital Asset Links)
  #   * iOS Universal Links — apple-app-site-association (extensionless or .json)
  #
  # These describe the same surface the client-side analyzers extract from
  # AndroidManifest.xml / *.entitlements, but from the host's perspective and
  # — for AASA — with the actual path patterns (`/buy/*`, `NOT /private/*`).
  #
  # Same model as the other mobile analyzers: one endpoint per declared path,
  # method "GET", semantics in `protocol` ("universal-link"). The associated
  # app id / package rides along in `metadata`. Excluded patterns (AASA `NOT `
  # / `exclude: true`) are still emitted, tagged `excluded`, since they are
  # part of the declared surface.
  class WellKnown < Analyzer
    # Digital Asset Links relation that delegates URL handling to the app —
    # the App Links grant. Other relations (e.g. get_login_creds) are not
    # deep-link surface and are ignored.
    HANDLE_ALL_URLS = "handle_all_urls"

    def analyze
      locator = CodeLocator.instance

      assetlinks = locator.all("android-assetlinks")
      assetlinks.each { |path| parse_safely(path) { |json| parse_assetlinks(json, path) } }

      aasa = locator.all("ios-aasa")
      aasa.each { |path| parse_safely(path) { |json| parse_aasa(json, path) } }

      @result
    end

    private def parse_safely(path : String, &)
      return unless File.exists?(path)
      content = read_file_content(path)
      yield JSON.parse(content)
    rescue e
      # Older AASA files may be CMS-signed (not plain JSON) — those fail here
      # and are skipped, per the v1 plain-JSON scope.
      @logger.debug "Failed to parse well-known link file #{path}: #{e.message}"
      @logger.debug_sub e
    end

    # assetlinks.json is an array of statements. Each android_app statement
    # that delegates `handle_all_urls` grants the app the whole hosting
    # domain, so we emit a single `/*` universal link carrying the package(s).
    private def parse_assetlinks(json : JSON::Any, path : String)
      statements = json.as_a?
      return unless statements

      packages = [] of String
      statements.each do |statement|
        next unless handles_all_urls?(statement)
        target = statement["target"]?
        next unless target
        next unless target["namespace"]?.try(&.as_s?) == "android_app"
        if package = target["package_name"]?.try(&.as_s?)
          packages << package unless package.empty? || packages.includes?(package)
        end
      end

      return if packages.empty?

      metadata = {} of String => String
      metadata["package"] = packages.join(", ")
      emit("/*", path, metadata: metadata)
    end

    private def handles_all_urls?(statement : JSON::Any) : Bool
      relations = statement["relation"]?.try(&.as_a?)
      return false unless relations
      relations.any? { |rel| rel.as_s?.try(&.ends_with?(HANDLE_ALL_URLS)) }
    end

    # apple-app-site-association declares an `applinks` object whose
    # `details` entries hold either legacy `paths` strings or the iOS 13+
    # `components` objects. Each pattern becomes one universal-link endpoint.
    private def parse_aasa(json : JSON::Any, path : String)
      applinks = json["applinks"]?
      return unless applinks
      details = applinks["details"]?.try(&.as_a?)
      return unless details

      seen = Set(String).new
      details.each do |detail|
        package = app_ids(detail)

        if paths = detail["paths"]?.try(&.as_a?)
          paths.each do |entry|
            next unless raw = entry.as_s?
            emit_aasa_path(raw, path, package, seen)
          end
        end

        if components = detail["components"]?.try(&.as_a?)
          components.each do |component|
            emit_aasa_component(component, path, package, seen)
          end
        end
      end
    end

    # Legacy `paths` form: a plain string, optionally prefixed with `NOT `
    # to mark an exclusion.
    private def emit_aasa_path(raw : String, path : String, package : String, seen : Set(String))
      pattern = raw.strip
      excluded = false
      if pattern.upcase.starts_with?("NOT ")
        excluded = true
        pattern = pattern[4..].strip
      end
      emit_link(pattern, path, package, excluded, seen)
    end

    # iOS 13+ `components` form: an object with a `/` path, optional `?`
    # query and `#` fragment matchers, and an `exclude` flag.
    private def emit_aasa_component(component : JSON::Any, path : String, package : String, seen : Set(String))
      pattern = component["/"]?.try(&.as_s?)
      return unless pattern
      excluded = truthy?(component["exclude"]?)
      params = query_params(component["?"]?)
      emit_link(pattern, path, package, excluded, seen, params)
    end

    private def emit_link(pattern : String, path : String, package : String,
                          excluded : Bool, seen : Set(String), params : Array(Param) = [] of Param)
      url = normalize_path(pattern)
      return if url.empty?
      return unless seen.add?(url)

      metadata = {} of String => String
      metadata["package"] = package unless package.empty?
      tags = excluded ? ["excluded"] : [] of String
      emit(url, path, params: params, metadata: metadata, tags: tags)
    end

    private def emit(url : String, path : String, params : Array(Param) = [] of Param,
                     metadata : Hash(String, String)? = nil, tags : Array(String) = [] of String)
      endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
      endpoint.protocol = "universal-link"
      endpoint.metadata = metadata if metadata && !metadata.empty?
      params.each { |param| endpoint.push_param(param) }
      tags.each do |tag|
        endpoint.add_tag(Tag.new(tag, "AASA exclusion pattern (does not open the app)", "well_known_applinks"))
      end
      @result << endpoint
    end

    # Joins a detail's app id(s) (legacy `appID` string or `appIDs` array,
    # each "TEAMID.bundle.id"). Empty when the detail declares none.
    private def app_ids(detail : JSON::Any) : String
      if ids = detail["appIDs"]?.try(&.as_a?)
        return ids.compact_map(&.as_s?).join(", ")
      end
      detail["appID"]?.try(&.as_s?) || ""
    end

    # A component `?` matcher is either a wildcard string (no named param) or
    # an object whose keys are query parameter names.
    private def query_params(node : JSON::Any?) : Array(Param)
      params = [] of Param
      return params unless node
      if hash = node.as_h?
        hash.each_key { |name| params << Param.new(name, "", "query") }
      end
      params
    end

    # Ensures a leading slash and keeps glob wildcards (`*`, `?`) as-is, the
    # closest Noir path form for these host-relative patterns.
    private def normalize_path(pattern : String) : String
      pattern = pattern.strip
      return "" if pattern.empty?
      pattern = "/#{pattern}" unless pattern.starts_with?('/')
      pattern
    end

    private def truthy?(node : JSON::Any?) : Bool
      return false unless node
      node.as_bool? == true
    end
  end
end
