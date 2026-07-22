require "xml"
require "../../../models/analyzer"
require "../../../miniparsers/swift_callee_extractor"

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
    # The app's "main" scheme + declared aliases — the first CFBundleURLTypes
    # array entry that resolves to any scheme, per Info.plist (see
    # `parse_info_plist`). Used to scope the code-level route harvesting
    # below so it doesn't cross unrelated auth/QR/bot schemes against every
    # harvested host.
    @primary_schemes = Set(String).new
    # scheme => every directory of an Info.plist that declared it primary.
    # The same literal scheme can legitimately show up as the first entry
    # in more than one Info.plist across a monorepo (an SDK/extension
    # target re-listing the main app's scheme for its own purposes,
    # unrelated to where that scheme's real routing code lives) — keeping
    # every occurrence, rather than just the first one seen, means
    # `best_matching_schemes` below can still find the *nearest* one to a
    # given piece of routing code instead of being pinned to whichever
    # Info.plist happened to be processed first.
    @primary_scheme_dirs = {} of String => Array(String)
    # Shared across the two code-level harvesting passes so a route found
    # both ways (or repeated across call sites) only surfaces once.
    @code_route_seen = Set(String).new
    # Budget counter for `harvest_literal_scheme_routes` only — kept
    # separate from `@code_route_seen` (shared dedup across both passes) so
    # a large batch of enum-harvested routes from `harvest_enum_host_routes`
    # can't exhaust literal harvesting's own MAX_LITERAL_ROUTES budget
    # before it scans a single file.
    @literal_route_count = 0

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

      harvest_enum_host_routes
      harvest_literal_scheme_routes

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
      # Only the first array entry that resolves to any real scheme is
      # treated as "primary" — this is the app's main scheme plus whatever
      # aliases it lists alongside it (e.g. `myapp` + `myapp-alt` in one
      # entry, or KakaoTalk's real vs. alpha-flavor build of the same
      # entry). Later entries are almost always narrow, single-purpose
      # schemes (auth callback, QR code, bot) that don't share the main
      # scheme's routing surface.
      primary_captured = false
      each_array_dict(url_types) do |entry|
        url_schemes = dict_value(entry, "CFBundleURLSchemes")
        next unless url_schemes

        entry_schemes = [] of String
        each_array_string(url_schemes) do |raw_scheme|
          next if raw_scheme.empty?
          # Xcode build-setting placeholders (`$(MOZ_PUBLIC_URL_SCHEME)`,
          # `${APPLICATION_SCHEME}`) are substituted at build time from
          # .xcconfig — resolve them here so Firefox/Element surface
          # `firefox://` / `element://` instead of the literal variable.
          resolved_schemes = substitute_build_vars(raw_scheme, build_vars)
          # Generic web/file schemes (registered e.g. so the app is
          # selectable as a browser) carry no app-specific deep-link
          # surface — a bare `http://` / `https://` is not an addressable
          # entry point, just noise in the inventory.
          resolved_schemes.each do |scheme|
            next if unresolved_build_var?(scheme)
            next if GENERIC_SCHEMES.includes?(scheme.downcase)
            entry_schemes << scheme

            url = "#{scheme}://"
            next unless seen.add?(url)

            endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
            endpoint.protocol = "mobile-scheme"
            @result << endpoint
          end
        end

        if !primary_captured && !entry_schemes.empty?
          plist_dir = File.dirname(File.expand_path(path))
          entry_schemes.each do |scheme|
            @primary_schemes << scheme
            dirs = @primary_scheme_dirs[scheme] ||= [] of String
            dirs << plist_dir unless dirs.includes?(plist_dir)
          end
          primary_captured = true
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
    # Presence-only gate for the same reference syntax. One precompiled
    # `Regex.union` scan (PCRE2 JIT) replaces the OR-ed
    # `String#includes?("$(")` / `String#includes?("${")` pair used to
    # short-circuit substitution/resolution below.
    BUILD_VAR_REF_RE = Regex.union("$(", "${")

    # Loads build-setting definitions from the project's .xcconfig and
    # project.pbxproj files, so CFBundleURLSchemes placeholders can be resolved.
    # Values are gathered from the enclosing Xcode project root and kept as a
    # small set per key because open-source repos often carry multiple app
    # flavors in one tree (e.g. Firefox Focus/Klar).
    private def load_xcconfig_vars(plist_path : String) : Hash(String, Array(String))
      # Generated-project tooling (Tuist, XcodeGen, Bazel's rules_apple, plain
      # SPM apps) commonly ships no `.xcodeproj`/`.xcworkspace` at all — those
      # are produced at build time and not checked in. Falling back to just
      # the plist's own directory then misses shared build settings kept in a
      # sibling directory (e.g. a top-level `Configs/`), silently dropping
      # every scheme that resolves through them. The scan's own configured
      # base is the best remaining signal of "the whole project" in that case.
      root = xcode_project_root(plist_path) || configured_base_for(plist_path)
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
      return [value] unless value.matches?(BUILD_VAR_REF_RE)

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
        break unless resolved.any?(&.matches?(BUILD_VAR_REF_RE))
      end
      resolved
    end

    private def unresolved_build_var?(value : String) : Bool
      value.matches?(BUILD_VAR_REF_RE)
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

      # Associated domains are just as likely to be build-setting placeholders
      # as CFBundleURLSchemes (e.g. `applinks:$(UNIVERSAL_LINKS_DOMAIN)`) — reuse
      # the same xcconfig/pbxproj resolution used for schemes so these don't
      # surface as literal, unusable `$(VAR)` hostnames.
      build_vars = load_xcconfig_vars(path)

      seen = Set(String).new
      each_array_string(domains) do |entry|
        # Entries look like "applinks:example.com", "appclips:example.com",
        # "applinks:example.com?mode=developer", "webcredentials:example.com".
        prefix = URL_DOMAIN_SERVICES.find { |p| entry.starts_with?(p) }
        next unless prefix
        domain = entry.lchop(prefix)
        domain = domain.split('?', 2).first.strip
        next if domain.empty?

        substitute_build_vars(domain, build_vars).each do |resolved_domain|
          next if unresolved_build_var?(resolved_domain)
          next if resolved_domain.empty?

          # An App Clip domain that the full app also serves as a universal link
          # is the same https:// surface; deduping on the URL collapses the two
          # while still surfacing App-Clip-only domains.
          url = "https://#{resolved_domain}/"
          next unless seen.add?(url)

          endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(path)))
          endpoint.protocol = "universal-link"
          @result << endpoint
        end
      end
    end

    # --- code-level route harvesting ---------------------------------------
    #
    # Info.plist only ever declares the bare `scheme://` — real apps route
    # `scheme://<host>/<path>` internally in code, which Info.plist has no
    # way to express. Two independent, source-derived signals recover part
    # of that surface:
    #
    #   A) `url.host == SomeEnum.someCase.rawValue` — the dominant idiom for
    #      apps with a real internal router (the host vocabulary lives in a
    #      String-backed enum, not a literal), harvested by resolving the
    #      enum's full case list and crossing it with `@primary_schemes`.
    #   B) Full `"scheme://host/path"` string literals hardcoded in source
    #      (debug menus, doc comments, tests) — no cross-product needed,
    #      the scheme is already embedded in the literal.
    #
    # Deliberately out of scope for both: same-file `switch expr.host {
    # case "x": }` / `if expr.host == "x"` literal parsing, and tracing a
    # host resolved in one file to path-level cases declared in another —
    # both measured (on a large real app) to add much less coverage per
    # unit of effort than A/B, and the former is prone to false positives
    # from in-app WebView JS-bridge schemes that reuse the exact same
    # `.host ==` idiom for unrelated purposes.

    # Path segments this codebase excludes everywhere iOS source is scanned
    # for handler/routing code: vendored dependencies, build output, and
    # test targets. Mirrors `NoirMobileLinker::IosHandlers.skip_ios_source?`
    # in `src/mobile/linker.cr` (private to that module, so not reusable
    # directly from here).
    private def ios_source_excluded?(path : String) : Bool
      normalized = path.gsub('\\', '/')
      basename = File.basename(normalized)
      normalized.includes?("/.build/") || normalized.includes?("/.swiftpm/") ||
        normalized.includes?("/Pods/") || normalized.includes?("/Carthage/") ||
        normalized.includes?("/DerivedData/") || normalized.includes?("/SourcePackages/") ||
        normalized.includes?("/Tests/") || normalized.includes?("/UITests/") ||
        normalized.includes?("/UnitTests/") || normalized.includes?("/SnapshotTests/") ||
        normalized.includes?("/TestSupport/") || normalized.includes?("/Generated/") ||
        basename.ends_with?("Tests.swift") || basename.ends_with?("Test.swift") ||
        basename.ends_with?(".generated.swift")
    end

    MAX_HOST_ENUMS     =  20
    MAX_CASES_PER_ENUM = 200

    # `.host`/`.scheme` connected to `EnumName.case.rawValue` via a
    # comparison (`==`/`!=`), an assignment (`=`), or membership in a
    # `[...].contains(...)` array literal — the shapes real routers use to
    # test/set a scheme's host against a String-backed enum. Deliberately
    # not a full expression parser: forms that separate the two sides
    # further (e.g. `url.host ?? "" == ...`) are missed in exchange for not
    # firing on two unrelated statements that merely share a line (a bare
    # `.host`/`.scheme` substring next to an unrelated capitalized-enum
    # `.rawValue` reference elsewhere on the same line).
    HOST_ENUM_SITE_RE = /\.(?:host|scheme)\S*\s*[=!]?=\s*([A-Z][A-Za-z0-9_]*)\.[A-Za-z_][A-Za-z0-9_]*\.rawValue|([A-Z][A-Za-z0-9_]*)\.[A-Za-z_][A-Za-z0-9_]*\.rawValue\s*[=!]?=\s*\S*\.(?:host|scheme)|\[[^\]\n]*\b([A-Z][A-Za-z0-9_]*)\.[A-Za-z_][A-Za-z0-9_]*\.rawValue[^\]\n]*\]\s*\.contains\(\s*\S*\.(?:host|scheme)/
    ENUM_CASE_LINE_RE = /^\s*case\s+(.+)$/
    ENUM_CASE_NAME_RE = /^([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*"([^"]*)")?$/

    private def harvest_enum_host_routes
      return if @primary_schemes.empty?

      swift_files = get_files_by_extension(".swift").reject { |p| ios_source_excluded?(p) }
      return if swift_files.empty?

      # enum name => the first file where it was seen driving a
      # `.host`/`.scheme` routing decision (used below to pick which app
      # target's scheme(s) this particular router enum belongs to). Depth
      # tracking is threaded through `strip_non_code_with_state` per file so
      # a `//` or brace inside a case's own string literal on an earlier
      # line can't be mistaken for a real comment/structure and corrupt the
      # scan of a later line.
      enum_sites = {} of String => String
      swift_files.each do |path|
        content = read_file_content(path)
        depth = 0
        in_string = false
        content.each_line do |line|
          break if enum_sites.size >= MAX_HOST_ENUMS
          stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)

          stripped.scan(HOST_ENUM_SITE_RE) do |m|
            enum_name = m[1]? || m[2]? || m[3]?
            enum_sites[enum_name] ||= path if enum_name
          end
        end
      rescue e
        @logger.debug "Failed scanning #{path} for scheme host enums: #{e.message}"
      end

      enum_sites.each do |enum_name, site_path|
        cases = resolve_enum_cases(enum_name, swift_files)
        next if cases.empty?

        schemes = best_matching_schemes(site_path)
        cases.first(MAX_CASES_PER_ENUM).each do |host, decl_path, decl_line|
          next if host.empty?

          schemes.each do |scheme|
            url = "#{scheme}://#{host}"
            next unless @code_route_seen.add?(url)

            endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(decl_path, decl_line)))
            endpoint.protocol = "mobile-scheme"
            @result << endpoint
          end
        end
      end
    end

    # A monorepo scan sees every app target's `@primary_schemes` at once, so
    # crossing a harvested host against *all* of them would graft one
    # target's whole routing table onto an unrelated target's scheme (e.g.
    # a shared enum's cases showing up under a small sample app's scheme
    # just because that sample app also has its own Info.plist somewhere in
    # the same tree). Prefer the scheme(s) whose Info.plist directory
    # shares the longest path prefix with `reference_path` — the file where
    # the enum was actually seen driving routing — ties included (this is
    # what keeps a scheme's own declared aliases, e.g. `myapp`+`myapp-alt`
    # from one CFBundleURLTypes entry, together).
    private def best_matching_schemes(reference_path : String) : Array(String)
      return @primary_schemes.to_a if @primary_scheme_dirs.empty?

      reference_segments = File.expand_path(reference_path).split('/')
      best_score = -1
      best = [] of String

      @primary_schemes.each do |scheme|
        dirs = @primary_scheme_dirs[scheme]?
        next unless dirs

        # A scheme can be declared primary in more than one Info.plist (an
        # unrelated SDK/extension target re-listing the main app's scheme
        # for its own purposes) — score against whichever declaration is
        # nearest to `reference_path`, not an arbitrary one.
        score = dirs.max_of { |dir| shared_path_prefix_length(reference_segments, dir.split('/')) }
        if score > best_score
          best_score = score
          best = [scheme]
        elsif score == best_score
          best << scheme
        end
      end

      best.empty? ? @primary_schemes.to_a : best
    end

    private def shared_path_prefix_length(a : Array(String), b : Array(String)) : Int32
      count = 0
      limit = a.size < b.size ? a.size : b.size
      while count < limit && a[count] == b[count]
        count += 1
      end
      count
    end

    # Finds `enum <enum_name>: String { ... }` and returns its case list as
    # {rawValue, declaring_file, line} — implicit raw values (bare `case
    # foo`) resolve to the case name itself; explicit ones (`case foo =
    # "bar"`) use the quoted literal.
    private def resolve_enum_cases(enum_name : String, swift_files : Array(String)) : Array(Tuple(String, String, Int32))
      decl_re = Regex.new("\\benum\\s+#{Regex.escape(enum_name)}\\s*:\\s*String\\b")

      swift_files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("enum #{enum_name}")

        lines = content.lines
        depth = 0
        in_string = false
        lines.each_with_index do |line, index|
          stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
          next unless stripped.matches?(decl_re)

          brace = find_opening_brace(lines, index)
          next unless brace

          body, body_start_line = enum_body_after_opening_brace(lines, brace[:index], brace[:col])
          return parse_enum_case_body(body, path, body_start_line)
        end
      rescue e
        @logger.debug "Failed scanning #{path} for enum #{enum_name}: #{e.message}"
      end

      [] of Tuple(String, String, Int32)
    end

    # Finds the first `{` at/after the enum's declaration line — same line
    # in the overwhelming majority of Swift style, else within a few lines
    # for a declaration that wraps.
    private def find_opening_brace(lines : Array(String), start : Int32) : NamedTuple(index: Int32, col: Int32)?
      idx = start
      while idx < lines.size && idx <= start + 6
        col = lines[idx].index('{')
        return {index: idx, col: col} if col
        idx += 1
      end
      nil
    end

    # Brace-matched body text starting just after lines[opening_index][col],
    # handling both a compact single-line body (`{ case a, b, c }`) and a
    # multi-line one. Depth is tracked on `strip_non_code_with_state`'s
    # output (comments AND string contents blanked) so a case's own raw
    # value — which may itself contain `//` or unbalanced braces — can't be
    # mistaken for real source structure and corrupt where the enum body
    # actually ends.
    private def enum_body_after_opening_brace(lines : Array(String), opening_index : Int32, col : Int32) : Tuple(String, Int32)
      first = lines[opening_index][(col + 1)..]? || ""
      clean, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first, 0, false)
      brace = 1 + clean.count('{') - clean.count('}')
      if brace <= 0
        closing = clean.rindex('}')
        return {closing ? first[0...closing] : first, opening_index + 1}
      end

      body = [first]
      idx = opening_index + 1
      while idx < lines.size && brace > 0
        line = lines[idx]
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        nxt = brace + stripped.count('{') - stripped.count('}')
        if nxt <= 0
          closing = stripped.rindex('}')
          body << (closing ? line[0...closing] : line) unless line.strip == "}"
          break
        end
        body << line
        brace = nxt
        idx += 1
      end

      {body.join("\n"), opening_index + 1}
    end

    # Walks the (already brace-matched) enum body text for `case ...`
    # declarations at the enum's own top level (depth 0 relative to the
    # body) — a nested `switch self { case .x: }` in a computed property
    # reuses the same `case ...:` shape and must not be mistaken for
    # another case declaration. Depth/case-line detection run on the
    # comment/string-blanked line (`stripped`); the actual name/raw value
    # is then read back from the original, unblanked `line` so a real
    # quoted raw value isn't lost to blanking.
    private def parse_enum_case_body(body : String, path : String, start_line : Int32) : Array(Tuple(String, String, Int32))
      cases = [] of Tuple(String, String, Int32)
      depth = 0
      in_string = false

      body.each_line.with_index do |line, offset|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)

        if depth == 0 && stripped.matches?(ENUM_CASE_LINE_RE) && (raw_match = line.match(ENUM_CASE_LINE_RE))
          parse_enum_case_names(raw_match[1]).each do |name, raw_value|
            break if cases.size >= MAX_CASES_PER_ENUM
            cases << {raw_value || name, path, start_line + offset}
          end
        end

        depth += stripped.count('{') - stripped.count('}')
      end

      cases
    end

    # `case a, b = "lit", c` -> [{"a", nil}, {"b", "lit"}, {"c", nil}].
    private def parse_enum_case_names(rest : String) : Array(Tuple(String, String?))
      results = [] of Tuple(String, String?)
      rest.split(',').each do |segment|
        trimmed = segment.strip
        next if trimmed.empty?
        next unless m = trimmed.match(ENUM_CASE_NAME_RE)

        results << {m[1], m[2]?}
      end
      results
    end

    MAX_LITERAL_ROUTES = 500

    # Full deep-link URLs hardcoded as string literals — Swift `"..."` or
    # Objective-C `@"..."` (same body syntax once the leading `@` is
    # allowed for). `(?:[^"\\ ]|\\.)*` stops at an unescaped quote *or* a
    # raw space, which both terminates the literal correctly and rejects
    # descriptive test-assertion strings that happen to start with a
    # scheme (`"kakaoopen:// without host should return false"`).
    private def harvest_literal_scheme_routes
      # Bare-scheme entries only (`"kakaotalk://"`) — by this point `@result`
      # also holds host-level routes from `harvest_enum_host_routes`
      # (`"kakaotalk://gift"`), which are not schemes to search for and
      # would otherwise bloat the alternation below with ~300 branches
      # instead of ~15.
      schemes = @result.compact_map do |ep|
        ep.protocol == "mobile-scheme" && ep.url.ends_with?("://") ? ep.url.rchop("://") : nil
      end.uniq!
      return if schemes.empty?

      escaped = schemes.map { |s| Regex.escape(s) }.join("|")
      literal_re = /@?"((?:#{escaped}):\/\/(?:[^"\\ ]|\\.)*)"/

      files = get_files_by_extensions([".swift", ".m", ".mm"]).reject { |p| ios_source_excluded?(p) }
      return if files.empty?

      files.each do |path|
        break if @literal_route_count >= MAX_LITERAL_ROUTES
        objc = path.ends_with?(".m") || path.ends_with?(".mm")
        content = read_file_content(path)

        content.each_line.with_index do |line, index|
          break if @literal_route_count >= MAX_LITERAL_ROUTES

          line.scan(literal_re) do |m|
            literal = m[1]
            # Swift string interpolation (`\(id)`) and Objective-C format
            # specifiers (`%@`) inside the literal are skipped rather than
            # templated — see the deferred-work note above the section
            # header. The plain literals (most of them) still land.
            next if literal.includes?("\\(")
            next if objc && literal.includes?('%')
            next unless @code_route_seen.add?(literal)

            @literal_route_count += 1
            endpoint = Endpoint.new(literal, "GET", Details.new(PathInfo.new(path, index + 1)))
            endpoint.protocol = "mobile-scheme"
            @result << endpoint
          end
        end
      rescue e
        @logger.debug "Failed scanning #{path} for literal scheme routes: #{e.message}"
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
