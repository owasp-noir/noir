require "xml"
require "../../../models/analyzer"

module Analyzer::Mobile
  # Parses iOS configuration files to surface mobile app entry points:
  #   * Info.plist  CFBundleURLTypes > CFBundleURLSchemes -> custom schemes
  #   * *.entitlements  com.apple.developer.associated-domains
  #                     applinks:<domain> -> universal links
  #
  # Same model as the Android analyzer: one endpoint per URI, method "GET",
  # mobile semantics in `protocol`. iOS declares no handler in the config
  # (deep links are dispatched by the App/SceneDelegate `onOpenURL` /
  # `application(_:open:)`), so `via` is filled later by the code layer.
  class Ios < Analyzer
    # Generic web/file schemes an app may register without them being a
    # real deep-link surface (a bare `http://` / `https://` has no host to
    # address). Compared case-insensitively.
    GENERIC_SCHEMES = Set{"http", "https", "file", "content"}

    @build_vars_cache = {} of String => Hash(String, Array(String))

    def analyze
      locator = CodeLocator.instance

      plists = locator.all("ios-info-plist")
      if plists.is_a?(Array(String))
        plists.each { |path| parse_safely(path) { |doc| parse_info_plist(doc, path) } }
      end

      entitlements = locator.all("ios-entitlements")
      if entitlements.is_a?(Array(String))
        entitlements.each { |path| parse_safely(path) { |doc| parse_entitlements(doc, path) } }
      end

      @result
    end

    private def parse_safely(path : String, &)
      return unless File.exists?(path)
      content = read_file_content(path)
      yield XML.parse(content)
    rescue e
      # Source repos ship XML plists; compiled/binary plists fail here.
      @logger.debug "Failed to parse iOS plist #{path}: #{e.message}"
      @logger.debug_sub e
    end

    private def parse_info_plist(doc : XML::Node, path : String)
      root = plist_root_dict(doc)
      return unless root

      url_types = dict_value(root, "CFBundleURLTypes")
      return unless url_types

      build_vars = load_xcconfig_vars(path)

      seen = Set(String).new
      each_array_dict(url_types) do |entry|
        schemes = dict_value(entry, "CFBundleURLSchemes")
        next unless schemes

        each_array_string(schemes) do |raw_scheme|
          next if raw_scheme.empty?
          # Xcode build-setting placeholders (`$(MOZ_PUBLIC_URL_SCHEME)`,
          # `${APPLICATION_SCHEME}`) are substituted at build time from
          # .xcconfig — resolve them here so Firefox/Element surface
          # `firefox://` / `element://` instead of the literal variable.
          schemes = substitute_build_vars(raw_scheme, build_vars)
          # Generic web/file schemes (registered e.g. so the app is
          # selectable as a browser) carry no app-specific deep-link
          # surface — a bare `http://` / `https://` is not an addressable
          # entry point, just noise in the inventory.
          schemes.each do |scheme|
            next if unresolved_build_var?(scheme)
            next if GENERIC_SCHEMES.includes?(scheme.downcase)
            url = "#{scheme}://"
            next unless seen.add?(url)

            endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
            endpoint.protocol = "mobile-scheme"
            @result << endpoint
          end
        end
      end
    end

    # How far up from the Info.plist to look for the project's build settings
    # files, and how many to read.
    XCCONFIG_SEARCH_DEPTH            =  6
    MAX_XCCONFIG_FILES               = 40
    MAX_PBXPROJ_FILES                = 10
    MAX_BUILD_VAR_VALUES_PER_KEY     = 16
    MAX_BUILD_VAR_EXPANSIONS         = 32
    MAX_BUILD_VAR_SUBSTITUTION_DEPTH =  8
    # `KEY = value` (xcconfig assignment); the value runs to a trailing
    # comment / end of line.
    XCCONFIG_ASSIGN_RE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\n]*)$/
    # `KEY = value;` (project.pbxproj build setting assignment).
    PBXPROJ_ASSIGN_RE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]*)\s*;\s*$/
    # `$(VAR)` / `${VAR}` build-setting reference.
    BUILD_VAR_RE = /\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]/

    # Loads build-setting definitions from the project's .xcconfig and
    # project.pbxproj files, so CFBundleURLSchemes placeholders can be resolved.
    # Values are gathered from the enclosing Xcode project root and kept as a
    # small set per key because open-source repos often carry multiple app
    # flavors in one tree (e.g. Firefox Focus/Klar).
    private def load_xcconfig_vars(plist_path : String) : Hash(String, Array(String))
      root = xcode_project_root(plist_path) || File.dirname(File.expand_path(plist_path))
      if cached = @build_vars_cache[root]?
        return cached
      end

      vars = {} of String => Array(String)
      Dir.glob(File.join(root, "**", "*.xcconfig")).sort.first(MAX_XCCONFIG_FILES).each do |xc|
        parse_xcconfig(xc, vars)
      end
      Dir.glob(File.join(root, "**", "project.pbxproj")).sort.first(MAX_PBXPROJ_FILES).each do |pbx|
        parse_pbxproj(pbx, vars)
      end
      @build_vars_cache[root] = vars
      vars
    end

    # The nearest ancestor of the Info.plist that holds a `.xcodeproj` /
    # `.xcworkspace`; nil if none within the search depth.
    private def xcode_project_root(plist_path : String) : String?
      dir = File.dirname(File.expand_path(plist_path))
      XCCONFIG_SEARCH_DEPTH.times do
        has_project = !Dir.glob(File.join(dir, "*.xcodeproj")).empty? ||
                      !Dir.glob(File.join(dir, "*.xcworkspace")).empty?
        return dir if has_project
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    private def parse_xcconfig(path : String, vars : Hash(String, Array(String)))
      read_file_content(path).each_line do |line|
        next if line.lstrip.starts_with?("//") || line.lstrip.starts_with?('#')
        next unless m = line.match(XCCONFIG_ASSIGN_RE)
        store_build_var(vars, m[1], clean_build_var_value(m[2]))
      end
    rescue e
      @logger.debug "Failed to parse xcconfig #{path}: #{e.message}"
    end

    private def parse_pbxproj(path : String, vars : Hash(String, Array(String)))
      read_file_content(path).each_line do |line|
        next unless m = line.match(PBXPROJ_ASSIGN_RE)
        store_build_var(vars, m[1], clean_build_var_value(m[2]))
      end
    rescue e
      @logger.debug "Failed to parse pbxproj #{path}: #{e.message}"
    end

    private def store_build_var(vars : Hash(String, Array(String)), key : String, value : String)
      return if value.empty? || value == "("

      values = vars[key] ||= [] of String
      return if values.includes?(value) || values.size >= MAX_BUILD_VAR_VALUES_PER_KEY

      values << value
    end

    private def clean_build_var_value(raw_value : String) : String
      value = raw_value.sub(%r{//.*$}, "").gsub("$(inherited)", "").strip
      if value.size >= 2 && value.starts_with?('"') && value.ends_with?('"')
        value = value[1...-1]
      end
      value.strip
    end

    # Resolves `$(VAR)` / `${VAR}` against the xcconfig map. Values in
    # xcconfig files may themselves point at another build setting
    # (`APP_SCHEME = ${BRANDED_SCHEME}`), so resolve repeatedly with a
    # bounded depth. Unknown or cyclic references are kept verbatim and
    # filtered by `unresolved_build_var?` before endpoint creation.
    private def substitute_build_vars(value : String, vars : Hash(String, Array(String))) : Array(String)
      return [value] unless value.includes?("$(") || value.includes?("${")

      resolved = [value]
      MAX_BUILD_VAR_SUBSTITUTION_DEPTH.times do
        changed = false
        next_values = [] of String

        resolved.each do |candidate|
          if match = candidate.match(BUILD_VAR_RE)
            if replacements = vars[match[1]]?
              replacements.each do |replacement|
                next_values << candidate.sub(match[0], replacement)
              end
              changed = true
            else
              next_values << candidate
            end
          else
            next_values << candidate
          end
        end

        next_values = next_values.uniq.first(MAX_BUILD_VAR_EXPANSIONS)
        break unless changed

        resolved = next_values
        break unless resolved.any? { |candidate| candidate.includes?("$(") || candidate.includes?("${") }
      end
      resolved
    end

    private def unresolved_build_var?(value : String) : Bool
      value.includes?("$(") || value.includes?("${")
    end

    # Associated-domain service prefixes that designate a URL entry point.
    #   * applinks   — a tapped https:// URL opens the full app (universal link)
    #   * appclips   — a tapped https:// URL launches the App Clip; same URL
    #                  mechanism, but a distinct (often less-trusted, friction-
    #                  reduced) surface that the App Clip target handles via
    #                  NSUserActivity. App Clip targets ship their own
    #                  *.entitlements that frequently list domains the main app
    #                  does NOT (e.g. pocket-casts `appclips:pocketcasts.net`),
    #                  so skipping them dropped a real entry point.
    # webcredentials / activitycontinuation are autofill/handoff plumbing, not
    # URL entry points, and stay ignored.
    URL_DOMAIN_SERVICES = {"applinks:", "appclips:"}

    private def parse_entitlements(doc : XML::Node, path : String)
      root = plist_root_dict(doc)
      return unless root

      domains = dict_value(root, "com.apple.developer.associated-domains")
      return unless domains

      seen = Set(String).new
      each_array_string(domains) do |entry|
        # Entries look like "applinks:example.com", "appclips:example.com",
        # "applinks:example.com?mode=developer", "webcredentials:example.com".
        prefix = URL_DOMAIN_SERVICES.find { |p| entry.starts_with?(p) }
        next unless prefix
        domain = entry.lchop(prefix)
        domain = domain.split('?', 2).first.strip
        next if domain.empty?

        # An App Clip domain that the full app also serves as a universal link
        # is the same https:// surface; deduping on the URL collapses the two
        # while still surfacing App-Clip-only domains.
        url = "https://#{domain}/"
        next unless seen.add?(url)

        endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
        endpoint.protocol = "universal-link"
        @result << endpoint
      end
    end

    # --- plist (XML) helpers ----------------------------------------------
    #
    # A plist dict is a flat list of alternating <key> / value element
    # siblings: <key>Name</key><string>v</string><key>Other</key><array>…</array>.

    private def plist_root_dict(doc : XML::Node) : XML::Node?
      plist = find_child(doc, "plist")
      return unless plist
      find_child(plist, "dict")
    end

    # Returns the value element that follows the <key> whose text == key.
    private def dict_value(dict : XML::Node?, key : String) : XML::Node?
      return unless dict
      pending_value = false
      dict.children.each do |child|
        next unless child.element?
        if pending_value
          return child
        end
        if child.name == "key" && child.content.strip == key
          pending_value = true
        end
      end
      nil
    end

    private def each_array_dict(array : XML::Node, &)
      return unless array.name == "array"
      array.children.each do |child|
        yield child if child.element? && child.name == "dict"
      end
    end

    private def each_array_string(array : XML::Node, &)
      return unless array.name == "array"
      array.children.each do |child|
        yield child.content.strip if child.element? && child.name == "string"
      end
    end

    private def find_child(node : XML::Node, local_name : String) : XML::Node?
      node.children.each do |c|
        return c if c.element? && c.name == local_name
      end
      nil
    end
  end
end
