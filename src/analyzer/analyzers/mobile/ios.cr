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
          scheme = substitute_build_vars(raw_scheme, build_vars)
          # Generic web/file schemes (registered e.g. so the app is
          # selectable as a browser) carry no app-specific deep-link
          # surface — a bare `http://` / `https://` is not an addressable
          # entry point, just noise in the inventory.
          next if GENERIC_SCHEMES.includes?(scheme.downcase)
          url = "#{scheme}://"
          next unless seen.add?(url)

          endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
          endpoint.protocol = "mobile-scheme"
          @result << endpoint
        end
      end
    end

    # How far up from the Info.plist to look for the project's .xcconfig
    # files, and how many to read.
    XCCONFIG_SEARCH_DEPTH =  6
    MAX_XCCONFIG_FILES    = 40
    # `KEY = value` (xcconfig assignment); the value runs to a trailing
    # comment / end of line.
    XCCONFIG_ASSIGN_RE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\n]*)$/
    # `$(VAR)` / `${VAR}` build-setting reference.
    BUILD_VAR_RE = /\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]/

    # Loads `KEY = value` definitions from the project's .xcconfig files, so
    # build-setting placeholders in CFBundleURLSchemes can be resolved. The
    # files are gathered from the enclosing Xcode project root (so variant
    # configs in Config/ or Variants/ are seen, not just the ones nearest the
    # Info.plist); first definition wins.
    private def load_xcconfig_vars(plist_path : String) : Hash(String, String)
      vars = {} of String => String
      root = xcode_project_root(plist_path) || File.dirname(File.expand_path(plist_path))
      Dir.glob(File.join(root, "**", "*.xcconfig")).sort.first(MAX_XCCONFIG_FILES).each do |xc|
        parse_xcconfig(xc, vars)
      end
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

    private def parse_xcconfig(path : String, vars : Hash(String, String))
      read_file_content(path).each_line do |line|
        next if line.lstrip.starts_with?("//") || line.lstrip.starts_with?('#')
        next unless m = line.match(XCCONFIG_ASSIGN_RE)
        value = m[2].sub(%r{//.*$}, "").gsub("$(inherited)", "").strip
        vars[m[1]] = value unless value.empty? || vars.has_key?(m[1])
      end
    rescue e
      @logger.debug "Failed to parse xcconfig #{path}: #{e.message}"
    end

    # Resolves `$(VAR)` / `${VAR}` against the xcconfig map; unknown
    # references are kept verbatim (same behavior as before this resolver).
    private def substitute_build_vars(value : String, vars : Hash(String, String)) : String
      return value unless value.includes?("$(") || value.includes?("${")
      value.gsub(BUILD_VAR_RE) { vars[$~[1]]? || $~[0] }
    end

    private def parse_entitlements(doc : XML::Node, path : String)
      root = plist_root_dict(doc)
      return unless root

      domains = dict_value(root, "com.apple.developer.associated-domains")
      return unless domains

      seen = Set(String).new
      each_array_string(domains) do |entry|
        # Entries look like "applinks:example.com", "applinks:example.com?mode=developer",
        # "webcredentials:example.com". Only applinks open the app from a URL.
        next unless entry.starts_with?("applinks:")
        domain = entry.lchop("applinks:")
        domain = domain.split('?', 2).first.strip
        next if domain.empty?

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
