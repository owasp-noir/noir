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

      seen = Set(String).new
      each_array_dict(url_types) do |entry|
        schemes = dict_value(entry, "CFBundleURLSchemes")
        next unless schemes

        each_array_string(schemes) do |scheme|
          next if scheme.empty?
          url = "#{scheme}://"
          next unless seen.add?(url)

          endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
          endpoint.protocol = "mobile-scheme"
          @result << endpoint
        end
      end
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
