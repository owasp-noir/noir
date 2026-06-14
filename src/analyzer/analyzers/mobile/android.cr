require "xml"
require "../../../models/analyzer"

module Analyzer::Mobile
  # Parses AndroidManifest.xml to surface mobile app entry points:
  #   * custom URL scheme deep links (intent-filter > data android:scheme)
  #   * verified App Links (autoVerify intent-filter on http/https)
  #   * exported components with a data-less action filter (IPC surface)
  #   * exported components with no intent-filter (explicit-intent surface)
  #   * exported ContentProviders (content://authority IPC surface)
  #   * Jetpack Navigation deep links (res/navigation/*.xml <deepLink>)
  #
  # One endpoint is emitted per deep-link URI; the handling component lives
  # in `metadata["via"]`, not a separate entry. A bare `intent://component`
  # endpoint models the Android IPC surface: it is emitted for an exported
  # component whose filter declares an action but no <data> URI (and isn't
  # the launcher), and for an exported component with no intent-filter at all
  # — the latter is still reachable by an explicit intent naming the component
  # (tagged `explicit` in metadata).
  #
  # All endpoints keep method = "GET"; the mobile semantics live in
  # `protocol` (mobile-scheme / universal-link / android-intent). `@string/`
  # values are resolved against res/values/strings.xml when present, and
  # gradle manifest placeholders (`${applicationId}`, custom
  # `manifestPlaceholders`) against the nearest build.gradle(.kts).
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

      strings = load_strings(path)
      gradle = load_gradle(path)
      placeholders = gradle.placeholders

      # Modern AGP projects omit the `package` attribute (the namespace /
      # applicationId live in build.gradle), and older ones may template it.
      package = substitute(attr(manifest, "package") || "", placeholders)
      package = gradle.package_fallback if package.empty?

      seen_urls = Set(String).new

      if application = find_child(manifest, "application")
        {"activity", "activity-alias", "service", "receiver"}.each do |component_tag|
          each_child(application, component_tag) do |component|
            process_component(component, component_tag, package, strings, placeholders, path, seen_urls)
          end
        end

        # Providers aren't reached by an intent naming the component; they are
        # addressed by `content://authority`, so they have their own surface.
        each_child(application, "provider") do |provider|
          process_provider(provider, package, strings, placeholders, path, seen_urls)
        end
      end

      parse_navigation_graphs(path, package, strings, placeholders, seen_urls)
    end

    private def process_component(component : XML::Node, component_tag : String,
                                  package : String, strings : Hash(String, String),
                                  placeholders : Hash(String, String),
                                  path : String, seen_urls : Set(String))
      # A component explicitly disabled in the manifest can't be launched
      # (until something re-enables it at runtime), so it isn't a live entry
      # point — skip it regardless of how it would otherwise be reached.
      return if attr(component, "enabled") == "false"

      exported = bool_attr(component, "exported")
      component_name = substitute(attr(component, "name") || "", placeholders)
      handler_name = component_tag == "activity-alias" ? substitute(attr(component, "targetActivity") || component_name, placeholders) : component_name

      filters = [] of XML::Node
      each_child(component, "intent-filter") { |f| filters << f }

      if filters.empty?
        # No intent-filter: a filter-less component defaults to NOT exported,
        # so it is reachable from another app only when `exported="true"` is
        # set explicitly — and then an explicit intent naming `package/component`
        # still reaches it without any action/category/data. The launcher is the
        # only filter-less component that is implicitly an app surface, and it
        # always declares a MAIN filter, so it never lands here.
        if exported
          emit_explicit_component_endpoint(component_name, handler_name, component_tag,
            package, attr(component, "permission"), path, seen_urls)
        end
        return
      end

      filters.each do |filter|
        actions = collect_names(filter, "action")
        categories = collect_names(filter, "category")
        data_nodes = [] of XML::Node
        each_child(filter, "data") { |d| data_nodes << d }
        auto_verify = bool_attr(filter, "autoVerify")

        if !data_nodes.empty?
          # Deep-link / app-link URI(s) — the primary entry points. The
          # handling component rides along as metadata["via"].
          emit_filter_endpoints(data_nodes, actions, categories, package, strings,
            placeholders, path, auto_verify, handler_name, seen_urls)
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

    # Generic/standard schemes carry no app-specific meaning on their own.
    # A host-less `http://` / `https://` / `file://` / `content://` is a
    # content-source qualifier — typically paired with a `<data mimeType>`
    # so the component can open a file type from a browser / file manager —
    # not a deep-link entry point. Custom schemes (`myapp://`) stay even
    # host-less, since that's how a runtime-routed custom scheme is declared.
    GENERIC_SCHEMES = Set{"http", "https", "file", "content"}

    # Local-content schemes. `file://` / `content://` URIs always point at
    # on-device content (a file picked from a file manager, a ContentProvider
    # row), never a remotely reachable deep link — so they are suppressed
    # regardless of host (including a bare `*` wildcard host).
    LOCAL_SCHEMES = Set{"file", "content"}

    # Opaque (authority-less) schemes: `mailto:foo@bar`, `tel:123`, `geo:…`.
    # They take no `//host` part, so the URL is rendered as `scheme:` rather
    # than `scheme://`. Deliberately conservative: `market://details?id=…`
    # (Play Store) and `mms://host` (media streaming, e.g. VLC) DO use an
    # authority, so they are NOT listed here.
    OPAQUE_SCHEMES = Set{"mailto", "tel", "sms", "smsto", "geo"}

    # Upper bound on endpoints emitted from a single intent-filter. A media
    # router / browser filter can declare dozens of hosts × paths; the full
    # cross product would flood the inventory with near-duplicates, so past
    # the cap the path dimension is dropped (scheme × host) and, if still
    # over, the result is truncated.
    MAX_FILTER_COMBOS = 64

    # Emits the deep-link endpoints for one intent-filter. Android matches a
    # URI against the filter as a whole, treating its `<data>` children as
    # independent sets: the scheme must be in the scheme set, the host (if
    # any) in the host set, and the path must satisfy one of the path rules.
    # A filter routinely splits `<data android:scheme=.../>` and
    # `<data android:host=... pathPrefix=.../>` across separate elements, so
    # the real surface is the cross product scheme × host × path — emitting
    # each `<data>` element on its own produced a bare `scheme://` and missed
    # the real `scheme://host/path`.
    private def emit_filter_endpoints(data_nodes : Array(XML::Node),
                                      actions : Array(String), categories : Array(String),
                                      package : String, strings : Hash(String, String),
                                      placeholders : Hash(String, String), path : String,
                                      auto_verify : Bool, via : String, seen_urls : Set(String))
      schemes = [] of String
      hosts = [] of String
      paths = [] of String
      has_mime_type = false

      data_nodes.each do |data|
        has_mime_type = true unless attr(data, "mimeType").nil?
        if scheme = resolve(attr(data, "scheme"), strings, placeholders)
          schemes << scheme unless scheme.empty? || schemes.includes?(scheme)
        end
        if host = resolve(attr(data, "host"), strings, placeholders)
          # A bare `*` host matches any authority — it carries no specific
          # target, so treat it as host-less (`scheme://*` == `scheme://`).
          # A wildcard *subdomain* (`*.example.com`) is kept as-is.
          hosts << host unless host.empty? || host == "*" || hosts.includes?(host)
        end
        norm = normalize_path(data, strings, placeholders)
        paths << norm unless norm.empty? || paths.includes?(norm)
      end
      return if schemes.empty?

      data_filter_combos(schemes, hosts, paths, has_mime_type).each do |scheme, host, norm_path|
        web = scheme == "http" || scheme == "https"
        url = build_data_url(scheme, host, norm_path)
        next unless seen_urls.add?(url)

        protocol = (web && auto_verify) ? "universal-link" : "mobile-scheme"
        endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
        endpoint.protocol = protocol
        endpoint.metadata = build_metadata(via, actions, categories, host, package)
        mark_unresolved(endpoint, url)
        @result << endpoint
      end
    end

    # Cross-products the scheme/host/path sets of one filter into
    # (scheme, host, path) triples, applying the host-less generic-scheme
    # suppression and the per-filter cap.
    private def data_filter_combos(schemes : Array(String), hosts : Array(String),
                                   paths : Array(String), has_mime_type : Bool) : Array({String, String, String})
      combos = [] of {String, String, String}
      effective_paths = paths.empty? ? [""] : paths

      schemes.each do |scheme|
        # Local-content schemes never describe a remote deep link.
        next if LOCAL_SCHEMES.includes?(scheme)
        if hosts.empty?
          # Host-less: keep only custom schemes. A generic scheme with no
          # host — and any scheme in a content-type (mimeType) filter — is a
          # file/content qualifier, not a remotely reachable deep link.
          next if has_mime_type || GENERIC_SCHEMES.includes?(scheme)
          combos << {scheme, "", ""}
        else
          hosts.each do |host|
            effective_paths.each { |norm_path| combos << {scheme, host, norm_path} }
          end
        end
      end

      return combos if combos.size <= MAX_FILTER_COMBOS

      # Over the cap: drop path granularity (scheme × host), then truncate.
      @logger.debug "Capping intent-filter deep links (#{combos.size} combinations) at #{MAX_FILTER_COMBOS}"
      collapsed = [] of {String, String, String}
      seen = Set(String).new
      combos.each do |scheme, host, _|
        collapsed << {scheme, host, ""} if seen.add?("#{scheme}://#{host}")
      end
      collapsed.first(MAX_FILTER_COMBOS)
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

    # Emits an android-intent endpoint for an exported component that declares
    # no intent-filter. Such a component can't be matched implicitly, but an
    # explicit intent naming `package/component` still reaches it, so it is part
    # of the IPC attack surface a security reviewer wants inventoried. Reuses
    # the synthetic intent:// scheme (so the optimizer/linker treat it like any
    # other intent component) and records the component kind, the explicit/
    # exported flags, and any guarding `android:permission` in metadata.
    private def emit_explicit_component_endpoint(component_name : String, handler_name : String,
                                                 component_tag : String, package : String,
                                                 permission : String?, path : String,
                                                 seen_urls : Set(String))
      component = component_name.empty? ? package : "#{package}/#{component_name}"
      url = "intent://#{component}"
      return unless seen_urls.add?(url)

      endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
      endpoint.protocol = "android-intent"

      metadata = {} of String => String
      # An activity-alias is addressed by its own name (kept in the URL), but
      # its handler code lives in the target activity — surface that as `via`
      # so the code linker resolves the right class.
      metadata["via"] = handler_name unless handler_name.empty? || handler_name == component_name
      metadata["component_type"] = component_tag
      metadata["exported"] = "true"
      metadata["explicit"] = "true"
      metadata["package"] = package unless package.empty?
      if perm = permission
        metadata["permission"] = perm unless perm.empty?
      end
      endpoint.metadata = metadata

      @result << endpoint
    end

    # Processes a `<provider>` (ContentProvider). Unlike the other components,
    # a provider isn't reached by an intent naming it — it is addressed by a
    # `content://<authority>` URI through a ContentResolver, so it is modeled
    # with its own `android-provider` protocol. Only an explicitly exported
    # provider is reported: pre-API-17 a provider defaulted to exported, but
    # modern tooling requires the attribute, so requiring `exported="true"`
    # keeps this conservative — matching how filter-less components are gated.
    private def process_provider(provider : XML::Node, package : String,
                                 strings : Hash(String, String),
                                 placeholders : Hash(String, String),
                                 path : String, seen_urls : Set(String))
      return if attr(provider, "enabled") == "false"
      return unless bool_attr(provider, "exported")

      raw_authorities = attr(provider, "authorities")
      return if raw_authorities.nil? || raw_authorities.empty?

      component_name = substitute(attr(provider, "name") || "", placeholders)

      metadata = {} of String => String
      # The provider class handles the surface, so surface it as `via` for the
      # code linker (an authority is rarely the class name).
      metadata["via"] = component_name unless component_name.empty?
      metadata["component_type"] = "provider"
      metadata["exported"] = "true"
      metadata["package"] = package unless package.empty?
      # Read/write may be guarded separately; the umbrella `android:permission`
      # covers both unless a more specific one overrides it. All are recorded,
      # not suppressed — the protection level (and so whether another app can
      # actually hold the permission) is the reviewer's call.
      add_permission(metadata, "permission", attr(provider, "permission"))
      add_permission(metadata, "read_permission", attr(provider, "readPermission"))
      add_permission(metadata, "write_permission", attr(provider, "writePermission"))
      metadata["grant_uri_permissions"] = "true" if provider_grants_uri?(provider)
      # `<path-permission>` children apply per-path overrides — frequently an
      # unprotected sub-path of an otherwise guarded provider. Flag their
      # presence so a reviewer inspects the granular rules; the effective
      # per-path permission is intentionally not guessed here.
      metadata["path_permissions"] = "true" if has_child?(provider, "path-permission")

      # `android:authorities` is a semicolon-separated list; each authority is
      # an independently addressable surface.
      raw_authorities.split(';').each do |raw_authority|
        authority = substitute(raw_authority.strip, placeholders)
        next if authority.empty?

        url = "content://#{authority}"
        next unless seen_urls.add?(url)

        endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
        endpoint.protocol = "android-provider"
        endpoint.metadata = metadata.dup
        mark_unresolved(endpoint, url)
        @result << endpoint
      end
    end

    # A provider grants ad-hoc URI access when `android:grantUriPermissions` is
    # set or it declares `<grant-uri-permission>` children — in either case a
    # caller can be handed temporary read/write access to specific URIs.
    private def provider_grants_uri?(provider : XML::Node) : Bool
      bool_attr(provider, "grantUriPermissions") || has_child?(provider, "grant-uri-permission")
    end

    private def add_permission(metadata : Hash(String, String), key : String, value : String?)
      return if value.nil? || value.empty?
      metadata[key] = value
    end

    # Renders a `<data>` URL. Opaque schemes (mailto/tel/geo/…) have no
    # `//authority`, so they're emitted as `scheme:`; everything else uses
    # the usual `scheme://host/path`.
    private def build_data_url(scheme : String, host : String, norm_path : String) : String
      return "#{scheme}:" if OPAQUE_SCHEMES.includes?(scheme)
      "#{scheme}://#{host}#{norm_path}"
    end

    # --- Jetpack Navigation (res/navigation/*.xml) -------------------------

    # Scheme emitted for scheme-less Navigation URIs. Navigation matches
    # both http and https for them; one canonical https endpoint keeps the
    # inventory free of http/https twins.
    NAV_DEFAULT_SCHEME = "https"
    NAV_VIEW_ACTION    = "android.intent.action.VIEW"

    # Jetpack Navigation graphs declare deep links outside the manifest:
    # res/navigation/*.xml <deepLink app:uri="..."> under a destination
    # (fragment / activity / dialog / nested <navigation>). They reuse the
    # mobile-scheme / universal-link model; the destination's android:name
    # becomes metadata["via"] so the code linker resolves the handler the
    # same way as a manifest component.
    private def parse_navigation_graphs(manifest_path : String, package : String,
                                        strings : Hash(String, String),
                                        placeholders : Hash(String, String),
                                        seen_urls : Set(String))
      nav_dir = File.join(File.dirname(manifest_path), "res", "navigation")
      return unless Dir.exists?(nav_dir)

      Dir.glob(File.join(nav_dir, "*.xml")).sort.each do |nav_path|
        begin
          doc = XML.parse(read_file_content(nav_path))
          root = find_child(doc, "navigation")
          next unless root
          walk_navigation(root, "", package, strings, placeholders, nav_path, seen_urls)
        rescue e
          @logger.debug "Failed to parse navigation graph #{nav_path}: #{e.message}"
          @logger.debug_sub e
        end
      end
    end

    # Recursively visits destinations, carrying the nearest android:name
    # down as the handling component for any <deepLink> beneath it (nested
    # <navigation> elements have no name of their own).
    private def walk_navigation(node : XML::Node, via : String, package : String,
                                strings : Hash(String, String),
                                placeholders : Hash(String, String),
                                nav_path : String, seen_urls : Set(String))
      node.children.each do |child|
        next unless child.element?
        if child.name == "deepLink"
          emit_nav_deep_link(child, via, package, strings, placeholders, nav_path, seen_urls)
        else
          child_via = resolve(attr(child, "name"), strings, placeholders) || via
          walk_navigation(child, child_via, package, strings, placeholders, nav_path, seen_urls)
        end
      end
    end

    # Emits one endpoint per <deepLink app:uri="...">. Navigation URIs may
    # omit the scheme (http/https implied), template path/query values with
    # `{arg}`, and end a path in a `.*` wildcard. Query placeholders become
    # `query` params and the query string is dropped from the URL, matching
    # how the HTTP analyzers model queries. mimeType/action-only deepLinks
    # (no uri) are not addressable from outside and are skipped.
    private def emit_nav_deep_link(node : XML::Node, via : String, package : String,
                                   strings : Hash(String, String),
                                   placeholders : Hash(String, String),
                                   nav_path : String, seen_urls : Set(String))
      uri = resolve(attr(node, "uri"), strings, placeholders)
      return if uri.nil? || uri.empty?

      if m = uri.match(%r{\A([A-Za-z][A-Za-z0-9+.\-]*)://})
        scheme = m[1]
        rest = uri[m[0].size..]
      else
        scheme = NAV_DEFAULT_SCHEME
        rest = uri.lchop("//")
      end

      rest, _, query = rest.partition('?')
      if slash = rest.index('/')
        host = rest[0...slash]
        raw_path = rest[slash..]
      else
        host = rest
        raw_path = ""
      end
      # A trailing `.*` is a wildcard match; keep the literal prefix.
      raw_path = raw_path.sub(/\.\*\z/, "")

      url = "#{scheme}://#{host}#{templatize(raw_path)}"
      return unless seen_urls.add?(url)

      web = scheme == "http" || scheme == "https"
      auto_verify = bool_attr(node, "autoVerify")
      protocol = (web && auto_verify) ? "universal-link" : "mobile-scheme"

      endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(nav_path)))
      endpoint.protocol = protocol
      action = attr(node, "action") || NAV_VIEW_ACTION
      endpoint.metadata = build_metadata(via, [action], [] of String, host, package)

      query.split('&').each do |pair|
        name = pair.partition('=')[0]
        endpoint.push_param(Param.new(name, "", "query")) unless name.empty?
      end

      mark_unresolved(endpoint, url)
      @result << endpoint
    end

    # --- gradle (${applicationId} / manifestPlaceholders) ------------------

    # Gradle-derived manifest context: the `${applicationId}` / custom
    # manifestPlaceholders substitution map, plus the module namespace /
    # applicationId used as a package fallback for manifests without a
    # `package` attribute.
    private struct GradleConfig
      getter application_id : String?
      getter namespace : String?
      getter placeholders : Hash(String, String)

      def initialize(@application_id, @namespace, @placeholders)
      end

      def self.empty
        new(nil, nil, {} of String => String)
      end

      def package_fallback : String
        application_id || namespace || ""
      end
    end

    # `applicationId "com.x"` (groovy) / `applicationId = "com.x"` (kts);
    # the quote requirement keeps `applicationIdSuffix` from matching.
    APPLICATION_ID_RE = /\bapplicationId\s*(?:=\s*)?["']([^"']+)["']/
    NAMESPACE_RE      = /\bnamespace\s*(?:=\s*)?["']([^"']+)["']/
    # Unquoted value: a gradle constant reference, e.g. `applicationId APP_ID`
    # (groovy) or `applicationId = NEWPIPE_APPLICATION_ID_OLD` (kts). The
    # `(?![A-Za-z0-9_])` after the key keeps `applicationIdSuffix` out, and
    # the UPPER_SNAKE value requirement keeps prose in a `// applicationId is
    # ...` comment from matching (gradle constants are upper-case by
    # convention; a camelCase val is intentionally not followed).
    APPLICATION_ID_CONST_RE = /\bapplicationId(?![A-Za-z0-9_])\s*(?:=\s*)?([A-Z][A-Z0-9_]+)\b/
    NAMESPACE_CONST_RE      = /\bnamespace(?![A-Za-z0-9_])\s*(?:=\s*)?([A-Z][A-Z0-9_]+)\b/
    # The bracketed segment after `manifestPlaceholders` — a groovy map
    # literal (`= [k: "v"]`), a kts `+= mapOf("k" to "v")`, or a
    # `putAll(mapOf(...))` — captured up to the first closing bracket.
    PLACEHOLDER_MAP_RE = /manifestPlaceholders[^\[(\n]*[\[(]([^\])]*)/
    # `key: "value"`, `"key": "value"` (groovy) and `"key" to "value"` (kts).
    PLACEHOLDER_PAIR_RE = /["']?([A-Za-z_]\w*)["']?\s*(?::|\bto\b)\s*["']([^"']*)["']/
    # `manifestPlaceholders["key"] = "value"` / `manifestPlaceholders.put("key", "value")` (kts).
    PLACEHOLDER_INDEX_RE = /manifestPlaceholders\s*\[\s*["'](\w+)["']\s*\]\s*=\s*["']([^"']*)["']/
    PLACEHOLDER_PUT_RE   = /manifestPlaceholders\s*\.\s*put\s*\(\s*["'](\w+)["']\s*,\s*["']([^"']*)["']\s*\)/

    private def load_gradle(manifest_path : String) : GradleConfig
      gradle_path = find_gradle_file(manifest_path)
      return GradleConfig.empty unless gradle_path

      begin
        parse_gradle(read_file_content(gradle_path), gradle_path)
      rescue e
        @logger.debug "Failed to parse gradle file #{gradle_path}: #{e.message}"
        GradleConfig.empty
      end
    end

    # The module build script lives above the manifest (`app/build.gradle`
    # vs `app/src/main/AndroidManifest.xml`); the nearest one wins so a
    # root-project script can't shadow the module's applicationId.
    private def find_gradle_file(manifest_path : String) : String?
      dir = File.dirname(File.expand_path(manifest_path))
      4.times do
        {"build.gradle", "build.gradle.kts"}.each do |name|
          candidate = File.join(dir, name)
          return candidate if File.exists?(candidate)
        end
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    # Regex-based extraction over both gradle DSLs. First occurrence wins,
    # so defaultConfig values (declared first by convention) take precedence
    # over buildType / flavor overrides; variant-specific placeholder values
    # are intentionally not modeled.
    private def parse_gradle(content : String, gradle_path : String) : GradleConfig
      # Prefer a quoted literal; fall back to a constant reference
      # (`applicationId APP_ID`) resolved against this script or buildSrc.
      # A quoted literal may itself be a groovy GString (`"${packageName}"`),
      # so resolve any interpolation it carries.
      application_id = content.match(APPLICATION_ID_RE).try(&.[1]) ||
                       resolve_const_ref(content, APPLICATION_ID_CONST_RE, gradle_path)
      application_id = resolve_gstring(application_id, content, gradle_path)
      namespace = content.match(NAMESPACE_RE).try(&.[1]) ||
                  resolve_const_ref(content, NAMESPACE_CONST_RE, gradle_path)
      namespace = resolve_gstring(namespace, content, gradle_path)
      placeholders = {} of String => String

      content.scan(PLACEHOLDER_MAP_RE) do |m|
        m[1].scan(PLACEHOLDER_PAIR_RE) do |pair|
          placeholders[pair[1]] = pair[2] unless placeholders.has_key?(pair[1])
        end
      end
      {PLACEHOLDER_INDEX_RE, PLACEHOLDER_PUT_RE}.each do |re|
        content.scan(re) do |m|
          placeholders[m[1]] = m[2] unless placeholders.has_key?(m[1])
        end
      end

      # AGP always provides ${applicationId} even without an explicit
      # manifestPlaceholders entry.
      if app_id = application_id
        placeholders["applicationId"] = app_id unless placeholders.has_key?("applicationId")
      end

      GradleConfig.new(application_id, namespace, placeholders)
    end

    # How far up from the module script to look for a `buildSrc/` source tree
    # holding shared gradle constants.
    BUILDSRC_SEARCH_DEPTH = 4

    # Resolves groovy GString interpolations (`applicationId "${packageName}"`)
    # in a captured applicationId / namespace value by looking each `${name}`
    # up as a gradle constant (same script, then buildSrc). The name comes
    # straight from `${...}`, so there is no loose prose-matching risk;
    # unknown names stay verbatim and nil passes through.
    private def resolve_gstring(value : String?, content : String, gradle_path : String) : String?
      return value if value.nil? || !value.includes?("${")
      value.gsub(/\$\{(\w+)\}/) { resolve_constant($~[1], content, gradle_path) || $~[0] }
    end

    # Matches a constant reference (`applicationId APP_ID`) and resolves the
    # named constant to its string literal. Returns nil when the value is not
    # a bare identifier (e.g. a method call) or the constant can't be found.
    private def resolve_const_ref(content : String, ref_re : Regex, gradle_path : String) : String?
      name = content.match(ref_re).try(&.[1])
      return unless name
      resolve_constant(name, content, gradle_path)
    end

    # Resolves a gradle constant to its string literal: the same build script
    # first (groovy `def APP_ID = "..."`), then a sibling `buildSrc/` source
    # tree (kotlin `const val APP_ID = "..."`), where multi-module projects
    # keep shared identifiers.
    private def resolve_constant(name : String, content : String, gradle_path : String) : String?
      def_re = /\b#{Regex.escape(name)}\s*=\s*["']([^"']+)["']/
      if m = content.match(def_re)
        return m[1]
      end
      resolve_buildsrc_constant(def_re, gradle_path)
    end

    private def resolve_buildsrc_constant(def_re : Regex, gradle_path : String) : String?
      dir = File.dirname(File.expand_path(gradle_path))
      BUILDSRC_SEARCH_DEPTH.times do
        buildsrc = File.join(dir, "buildSrc")
        if Dir.exists?(buildsrc)
          {"*.kt", "*.kts", "*.gradle"}.each do |pattern|
            Dir.glob(File.join(buildsrc, "**", pattern)).sort.each do |src|
              begin
                if m = read_file_content(src).match(def_re)
                  return m[1]
                end
              rescue
                next
              end
            end
          end
          return # buildSrc found but constant absent — stop walking up
        end
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    # Replaces `${placeholder}` references with their gradle values; unknown
    # placeholders are kept verbatim so `mark_unresolved` can tag them.
    private def substitute(value : String, placeholders : Hash(String, String)) : String
      return value unless value.includes?("${")
      value.gsub(/\$\{(\w+)\}/) { |s| placeholders[$~[1]]? || s }
    end

    # -----------------------------------------------------------------------

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
    private def normalize_path(data : XML::Node, strings : Hash(String, String),
                               placeholders : Hash(String, String)) : String
      if path = resolve(attr(data, "path"), strings, placeholders)
        return templatize(path)
      end
      if prefix = resolve(attr(data, "pathPrefix"), strings, placeholders)
        return templatize(prefix)
      end
      if pattern = resolve(attr(data, "pathPattern"), strings, placeholders)
        # Patterns are regex-ish (.* / .*foo); keep the literal prefix only.
        literal = pattern.split(/[.*\\]/).first
        return templatize(literal)
      end
      ""
    end

    # The `$` lookbehind keeps an unresolved gradle `${placeholder}` intact
    # (for the unresolved tag) while `{id}` still becomes `:id`.
    private def templatize(path : String) : String
      path.gsub(/(?<!\$)\{([^}]+)\}/, ":\\1")
    end

    private def mark_unresolved(endpoint : Endpoint, url : String)
      return unless url.includes?("@string/") || url.includes?("@{") || url.includes?("${")
      endpoint.add_tag(Tag.new("unresolved", "Contains an unresolved manifest reference", "android"))
    end

    # Resolves @string/foo against res/values/strings.xml and gradle
    # `${placeholder}` references; leaves any other value as-is and passes
    # nil through.
    private def resolve(value : String?, strings : Hash(String, String),
                        placeholders : Hash(String, String)) : String?
      return value if value.nil?
      if value.starts_with?("@string/")
        key = value.lchop("@string/")
        value = strings[key]? || value
      end
      substitute(value, placeholders)
    end

    # Loads <string> resources from every res/values/*.xml file. Android
    # merges string resources across all value files, not just strings.xml —
    # apps routinely keep deep-link bits elsewhere (e.g. Tusky declares its
    # oauth_scheme in donottranslate.xml). Returns name→value (first
    # definition wins); empty if the values directory is absent.
    private def load_strings(manifest_path : String) : Hash(String, String)
      strings = {} of String => String
      values_dir = File.join(File.dirname(manifest_path), "res", "values")
      return strings unless Dir.exists?(values_dir)

      Dir.glob(File.join(values_dir, "*.xml")).sort.each do |path|
        begin
          doc = XML.parse(read_file_content(path))
          next unless resources = find_child(doc, "resources")
          each_child(resources, "string") do |node|
            name = attr(node, "name")
            strings[name] = node.content if name && !strings.has_key?(name)
          end
        rescue e
          @logger.debug "Failed to parse values file #{path}: #{e.message}"
        end
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
    # falls back to a non-namespaced match (e.g. `package` on <manifest>,
    # `app:uri` on a navigation <deepLink>).
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

    private def has_child?(node : XML::Node, local_name : String) : Bool
      !find_child(node, local_name).nil?
    end

    private def each_child(node : XML::Node, local_name : String, &)
      node.children.each do |c|
        yield c if c.element? && c.name == local_name
      end
    end
  end
end
