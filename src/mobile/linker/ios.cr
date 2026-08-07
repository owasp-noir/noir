# Part of NoirMobileLinker: iOS deep-link dispatch — onOpenURL/userActivity handler
# discovery, callees and query params (IosHandlers).
module NoirMobileLinker
  # iOS: deep links are dispatched centrally (App/SceneDelegate), so there is
  # no per-endpoint `via`. Discover handlers within the endpoint's Xcode
  # project root and attach by kind — URL handlers (onOpenURL /
  # application(open:) / scene(openURLContexts:)) to custom schemes,
  # userActivity handlers to universal links. Scoping matters for monorepos
  # that ship multiple iOS apps; a Focus AppDelegate should not become Firefox
  # Browser evidence just because both live in the same repository checkout.
  private def self.link_ios(endpoints : Array(Endpoint), logger : NoirLogger)
    return unless endpoints.any? { |ep| ios_handler_target?(ep) }

    handlers_by_scope = {} of String => Hash(Symbol, HandlerInfo)

    endpoints.each_with_index do |endpoint, i|
      next unless ios_handler_target?(endpoint)
      scope = ios_handler_scope(endpoint)
      key = scope || ""
      handlers = handlers_by_scope[key]?
      unless handlers
        begin
          handlers = IosHandlers.discover(scope)
          handlers_by_scope[key] = handlers
        rescue e
          logger.debug "Mobile linker (iOS) handler discovery failed#{scope ? " for #{scope}" : ""}: #{e.message}"
          next
        end
      end

      info = endpoint.protocol == "universal-link" ? handlers[:activity] : handlers[:url]
      next if info.empty?
      endpoints[i] = apply_handler_info(endpoint, info)
    end
  end

  private def self.ios_handler_target?(endpoint : Endpoint) : Bool
    endpoint.mobile? && endpoint.details.technology == "ios"
  end

  private def self.ios_handler_scope(endpoint : Endpoint) : String?
    config_path = endpoint.details.code_paths.find do |path_info|
      File.basename(path_info.path) == "Info.plist" || path_info.path.ends_with?(".entitlements")
    end || endpoint.details.code_paths.first?
    return unless config_path

    IosHandlers.xcode_project_root(config_path.path) || IosHandlers.nearest_handler_source_root(config_path.path)
  end

  # Scans .swift files once for the central deep-link dispatch handlers and
  # groups their callees/params by kind. URL handlers process custom schemes;
  # userActivity handlers process universal links.
  module IosHandlers
    # Same-line markers for the brace that opens a handler body.
    URL_HANDLER_RES = [
      /\.onOpenURL\s*\{/,
      /\bfunc\s+application\s*\(.*\bopen\s+url\s*:/,
      /\bfunc\s+scene\s*\(.*\bopenURLContexts\b/,
    ]
    ACTIVITY_HANDLER_RES = [
      /\bfunc\s+application\s*\(.*\bcontinue\s+userActivity\s*:/,
      /\bfunc\s+scene\s*\(.*\bcontinue\s+userActivity\s*:/,
      /\.onContinueUserActivity\s*\(/,
    ]
    # Opening of an `application(...)` / `scene(...)` delegate method whose
    # parameter list may wrap across lines; used to fold the signature
    # before classifying it against the handler patterns above.
    SIGNATURE_START_RE = /\bfunc\s+(?:application|scene)\s*\(/

    # Objective-C counterparts. The same delegate methods are written as
    # message-style declarations: `- (BOOL)application:(UIApplication *)app
    # openURL:(NSURL *)url options:…`. Matched on the folded signature, so a
    # wrapped parameter list still classifies.
    OBJC_URL_HANDLER_RES = [
      /\bapplication:.*\bopenURL:/,
      /\bscene:.*\bopenURLContexts:/,
    ]
    OBJC_ACTIVITY_HANDLER_RES = [
      /\bapplication:.*\bcontinueUserActivity:/,
      /\bscene:.*\bcontinueUserActivity:/,
    ]
    OBJC_SIGNATURE_START_RE = /^\s*[+-]\s*\([^)]*\)\s*(?:application|scene):/

    # URLQueryItem name comparisons inside a handler — the iOS analog of
    # Android's getQueryParameter. Anchored to the closure-shorthand form
    # (`$0.name == "x"`) and an explicit `URLQueryItem(name: "x")` so a plain
    # `user.name == "admin"` comparison can't become a phantom query param.
    QUERY_NAME_RE = /\$\d+\.name\s*==\s*"([^"]+)"/
    QUERY_ITEM_RE = /URLQueryItem\(\s*name:\s*"([^"]+)"/

    # Objective-C query reads. The dominant idiom is iterating
    # `components.queryItems` and comparing the item's `name` against a
    # literal — `[item.name isEqualToString:@"token"]` (e.g. VLC reads
    # plexToken / payment_intent this way). Anchored to `.name` / `name]`
    # (not a bare `isEqualToString:`) so a `[host isEqualToString:@"new"]`
    # check can't become a phantom param. Also the explicit query-item
    # constructor.
    OBJC_QUERY_NAME_RE = /(?:\.name|\bname\])\s+isEqualToString:\s*@"([^"]+)"/
    OBJC_QUERY_ITEM_RE = /\bqueryItemWithName:\s*@"([^"]+)"/

    SWIFT_HANDLER_HINTS = [
      "openURLContexts",
      "open url:",
      "continue userActivity:",
      ".onOpenURL",
      ".onContinueUserActivity",
    ]
    OBJC_HANDLER_HINTS = [
      "openURL:",
      "openURLContexts:",
      "continueUserActivity:",
    ]

    IOS_CALLEE_NOISE = Set{
      "URL",
      "URLRequest",
      "URLComponents",
      "NSURLComponents",
      "componentsWithURL",
      "isEqualToString",
      "host",
      "shared",
      "URLContexts.first",
      "print",
      "Task",
      "UIApplication.shared.canOpenURL",
      "Notification.Name",
      "NotificationCenter.default.post",
      "UserDefaults.standard.bool",
      "AppContainer.shared.resolve",
      "routeBuilder.configure",
    }

    XCODE_PROJECT_SEARCH_DEPTH =  6
    MAX_FORWARDED_ACTIONS      =  8
    MAX_FORWARDED_CASES        = 24

    record ForwardedAction, receiver : String, method : String, action : String, action_type : String

    def self.discover(scope_root : String? = nil) : Hash(Symbol, NoirMobileLinker::HandlerInfo)
      url = NoirMobileLinker::HandlerInfo.new
      activity = NoirMobileLinker::HandlerInfo.new
      expanded_scope = scope_root.try { |root| File.expand_path(root).rstrip('/') }

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_scope)
        next if skip_ios_source?(path, expanded_scope)
        content = NoirMobileLinker.read_content(path)
        next unless content
        next unless swift_handler_candidate?(content)
        scan_file(path, content, url, activity,
          URL_HANDLER_RES, ACTIVITY_HANDLER_RES, SIGNATURE_START_RE, expanded_scope, objc: false)
      end

      {".m", ".mm"}.each do |ext|
        CodeLocator.instance.files_by_extension(ext).each do |path|
          next unless in_scope?(path, expanded_scope)
          next if skip_ios_source?(path, expanded_scope)
          content = NoirMobileLinker.read_content(path)
          next unless content
          next unless objc_handler_candidate?(content)
          scan_file(path, content, url, activity,
            OBJC_URL_HANDLER_RES, OBJC_ACTIVITY_HANDLER_RES, OBJC_SIGNATURE_START_RE, expanded_scope, objc: true)
        end
      end

      {:url => url, :activity => activity}
    end

    def self.xcode_project_root(path : String) : String?
      dir = File.dirname(File.expand_path(path))
      XCODE_PROJECT_SEARCH_DEPTH.times do
        has_project = !Dir.glob(File.join(dir, "*.xcodeproj")).empty? ||
                      !Dir.glob(File.join(dir, "*.xcworkspace")).empty?
        return dir if has_project
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    def self.nearest_handler_source_root(path : String) : String?
      dir = File.dirname(File.expand_path(path))
      XCODE_PROJECT_SEARCH_DEPTH.times do
        return dir if ios_handler_source_under?(dir)

        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    private def self.in_scope?(path : String, scope_root : String?) : Bool
      return true unless scope_root

      expanded = File.expand_path(path)
      expanded == scope_root || expanded.starts_with?(scope_root + "/")
    end

    private def self.ios_handler_source_under?(root : String) : Bool
      expanded_root = File.expand_path(root).rstrip('/')

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_root)
        next if skip_ios_source?(path, expanded_root)
        content = NoirMobileLinker.read_content(path)
        return true if content && swift_handler_candidate?(content)
      end

      {".m", ".mm"}.each do |ext|
        CodeLocator.instance.files_by_extension(ext).each do |path|
          next unless in_scope?(path, expanded_root)
          next if skip_ios_source?(path, expanded_root)
          content = NoirMobileLinker.read_content(path)
          return true if content && objc_handler_candidate?(content)
        end
      end

      false
    end

    # `scope_root` is the Xcode project root the caller already resolved.
    # The directory conventions below describe a location inside that
    # project, so they are matched on the project-relative path — on the
    # absolute path a `Tests/` directory anywhere above the checkout
    # excluded every source file in it. With no scope root there is
    # nothing to relativise against, and the whole path is matched as
    # before.
    private def self.skip_ios_source?(path : String, scope_root : String? = nil) : Bool
      relative = scope_root ? Noir::PathScope.relative_under(path, scope_root) : path
      normalized = relative.gsub('\\', '/')
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
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

    private def self.swift_handler_candidate?(content : String) : Bool
      SWIFT_HANDLER_HINTS.any? { |hint| content.includes?(hint) }
    end

    private def self.objc_handler_candidate?(content : String) : Bool
      OBJC_HANDLER_HINTS.any? { |hint| content.includes?(hint) }
    end

    # Scans one source file for the central deep-link dispatch handlers,
    # accumulating callees (and Swift query params) into the shared
    # `url` / `activity` handler info. `objc` selects the Objective-C handler
    # patterns + callee extractor; otherwise the Swift ones are used.
    private def self.scan_file(path : String, content : String,
                               url : NoirMobileLinker::HandlerInfo,
                               activity : NoirMobileLinker::HandlerInfo,
                               url_res : Array(Regex), activity_res : Array(Regex),
                               sig_re : Regex, expanded_scope : String?, objc : Bool)
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)

        # A handler's signature may span several lines (SwiftLint / Objective-C
        # both wrap long parameter lists), e.g.
        #   func application(
        #     _ app: UIApplication,
        #     open url: URL
        #   ) -> Bool {
        # so when a line opens such a signature, fold it through to the body
        # brace before matching — otherwise no single line carries both the
        # method name and the `openURL` / `continueUserActivity` discriminator.
        signature = stripped
        if stripped.matches?(sig_re) && !stripped.includes?('{')
          if sig_brace = find_opening_brace(lines, index)
            signature = lines[index..sig_brace[:index]].join(" ")
          end
        end

        target = if url_res.any? { |re| signature.matches?(re) }
                   url
                 elsif activity_res.any? { |re| signature.matches?(re) }
                   activity
                 end
        next unless target

        brace = find_opening_brace(lines, index)
        next unless brace
        body, body_line = body_after_opening_brace(lines, brace[:index], brace[:col])

        append_code_path(target, path, index + 1)
        callees = objc ? Noir::ObjcCalleeExtractor.callees_for_body(body, path, body_line) : Noir::SwiftCalleeExtractor.callees_for_body(body, path, body_line)
        append_callees(target, callees)
        # Query params read from the inbound URL, per dialect.
        name_re, item_re = objc ? {OBJC_QUERY_NAME_RE, OBJC_QUERY_ITEM_RE} : {QUERY_NAME_RE, QUERY_ITEM_RE}
        append_query_params(target, body, name_re, item_re)

        next if objc

        append_swift_local_method_info(path, content, callees, target, name_re, item_re)
        append_swift_forwarded_action_info(body, content, expanded_scope, target, name_re, item_re)
      end
    end

    private def self.append_code_path(info : NoirMobileLinker::HandlerInfo, path : String, line : Int32)
      return if info.code_paths.any? { |pi| pi.path == path && pi.line == line }

      info.code_paths << PathInfo.new(path, line)
    end

    private def self.append_callees(info : NoirMobileLinker::HandlerInfo, callees : Array(Tuple(String, String, Int32)))
      callees.each do |name, fpath, fline|
        next if ios_callee_noise?(name)
        next if info.callees.any? { |callee| callee.name == name && callee.path == fpath }

        info.callees << Callee.new(name, path: fpath, line: fline)
      end
    end

    private def self.append_query_params(info : NoirMobileLinker::HandlerInfo, body : String, name_re : Regex, item_re : Regex)
      body.scan(name_re) { |m| append_query_param(info, m[1]) }
      body.scan(item_re) { |m| append_query_param(info, m[1]) }
    end

    private def self.append_query_param(info : NoirMobileLinker::HandlerInfo, name : String)
      return if info.params.any? { |param| param.name == name && param.param_type == "query" }

      info.params << Param.new(name, "", "query")
    end

    # Many iOS apps keep the delegate handler tiny and immediately forward the
    # inbound URL to a same-file helper (`routeOpenURL(url)`,
    # `handleDeepLink(url)`). Follow only URL/deep-link-shaped helpers one
    # level so AI context sees the real sinks/guards without walking arbitrary
    # application call graphs.
    private def self.append_swift_local_method_info(path : String, content : String,
                                                    callees : Array(Tuple(String, String, Int32)),
                                                    target : NoirMobileLinker::HandlerInfo,
                                                    name_re : Regex, item_re : Regex)
      seen = Set(String).new
      callees.each do |name, _, _|
        next unless local_swift_method_candidate?(name)
        next unless seen.add?(name)
        method = swift_method_body(content, name)
        next unless method

        append_code_path(target, path, method[:line])
        nested = Noir::SwiftCalleeExtractor.callees_for_body(method[:body], path, method[:body_line])
        append_callees(target, nested)
        append_query_params(target, method[:body], name_re, item_re)
      end
    end

    # DuckDuckGo-style lifecycle code forwards `application(_:open:)` into a
    # state machine action: `appStateMachine.handle(.openURL(url))`, with the
    # real branch in `case .openURL`. Follow URL/deep-link action cases within
    # the same Xcode project scope, then apply the same local-helper expansion
    # to the case body.
    private def self.append_swift_forwarded_action_info(body : String,
                                                        handler_content : String,
                                                        expanded_scope : String?,
                                                        target : NoirMobileLinker::HandlerInfo,
                                                        name_re : Regex, item_re : Regex)
      actions = forwarded_swift_actions(body, handler_content, expanded_scope)
      return if actions.empty?

      cases_seen = 0
      actions.each do |action|
        CodeLocator.instance.files_by_extension(".swift").each do |path|
          next unless in_scope?(path, expanded_scope)
          next if skip_ios_source?(path, expanded_scope)
          content = NoirMobileLinker.read_content(path)
          next unless content
          next unless content.includes?("case .#{action.action}")

          cases_seen += scan_swift_action_cases(path, content, action, target, name_re, item_re, MAX_FORWARDED_CASES - cases_seen)
          return if cases_seen >= MAX_FORWARDED_CASES
        end
      end
    end

    private def self.forwarded_swift_actions(body : String, handler_content : String,
                                             expanded_scope : String?) : Array(ForwardedAction)
      actions = [] of ForwardedAction
      body.scan(/(?:self\.)?([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |m|
        receiver = m[1]
        method = m[2]
        action = m[3]
        next unless swift_deep_link_name?(action)
        receiver_type = swift_receiver_type(handler_content, receiver)
        next unless receiver_type
        action_type = swift_forwarded_action_type(receiver_type, method, action, expanded_scope)
        next unless action_type
        forwarded = ForwardedAction.new(receiver, method, action, action_type)
        next if actions.any? { |existing| existing == forwarded }

        actions << forwarded
        break if actions.size >= MAX_FORWARDED_ACTIONS
      end
      actions
    end

    private def self.scan_swift_action_cases(path : String, content : String, action : ForwardedAction,
                                             target : NoirMobileLinker::HandlerInfo,
                                             name_re : Regex, item_re : Regex,
                                             remaining : Int32) : Int32
      return 0 if remaining <= 0

      found = 0
      case_re = Regex.new("^\\s*case\\s+\\.#{Regex.escape(action.action)}\\b")

      swift_method_bodies(content, action.method, action.action_type).each do |method|
        lines = method[:body].lines
        depth = 0
        in_string = false

        lines.each_with_index do |line, index|
          stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
          next unless stripped.matches?(case_re)

          case_body, relative_body_line = swift_case_body(lines, index)
          case_line = method[:body_line] + index
          body_line = method[:body_line] + relative_body_line - 1
          append_code_path(target, path, case_line)
          callees = Noir::SwiftCalleeExtractor.callees_for_body(case_body, path, body_line)
          append_callees(target, callees)
          append_query_params(target, case_body, name_re, item_re)
          append_swift_local_method_info(path, content, callees, target, name_re, item_re)

          found += 1
          return found if found >= remaining
        end
      end

      found
    end

    private def self.swift_receiver_type(content : String, receiver : String) : String?
      escaped = Regex.escape(receiver)
      explicit_re = Regex.new("\\b(?:let|var)\\s+#{escaped}\\s*:\\s*([A-Za-z_][A-Za-z0-9_]*)\\b")
      inferred_re = Regex.new("\\b(?:let|var)\\s+#{escaped}\\s*=\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")

      content.match(explicit_re).try(&.[1]) || content.match(inferred_re).try(&.[1])
    end

    private def self.swift_forwarded_action_type(receiver_type : String, method : String, action : String,
                                                 expanded_scope : String?) : String?
      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_scope)
        next if skip_ios_source?(path, expanded_scope)
        content = NoirMobileLinker.read_content(path)
        next unless content
        next unless content.includes?(receiver_type) && content.includes?("func #{method}")

        swift_type_method_parameter_types(content, receiver_type, method).each do |action_type|
          return action_type if swift_enum_has_case?(action_type, action, expanded_scope)
        end
      end

      nil
    end

    private def self.swift_type_method_parameter_types(content : String, receiver_type : String,
                                                       method : String) : Array(String)
      type_re = Regex.new("\\b(?:class|struct|actor|enum)\\s+#{Regex.escape(receiver_type)}\\b")
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(type_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        body, _ = body_after_opening_brace(lines, brace[:index], brace[:col])
        return swift_method_parameter_types(body, method)
      end

      [] of String
    end

    private def self.swift_method_parameter_types(content : String, method : String) : Array(String)
      types = [] of String
      method_re = Regex.new("\\bfunc\\s+#{Regex.escape(method)}\\s*\\(")
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(method_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        signature = lines[index..brace[:index]].join(" ")
        signature.scan(/:\s*([A-Za-z_][A-Za-z0-9_]*)\b/) do |m|
          type = m[1]
          types << type unless types.includes?(type)
        end
      end

      types
    end

    private def self.swift_enum_has_case?(enum_name : String, case_name : String,
                                          expanded_scope : String?) : Bool
      enum_re = Regex.new("\\benum\\s+#{Regex.escape(enum_name)}\\b")
      case_re = Regex.new("^\\s*case\\s+#{Regex.escape(case_name)}\\b")

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_scope)
        next if skip_ios_source?(path, expanded_scope)
        content = NoirMobileLinker.read_content(path)
        next unless content
        next unless content.includes?("enum #{enum_name}") && content.includes?("case #{case_name}")

        lines = content.lines
        lines.each_with_index do |line, index|
          next unless line.matches?(enum_re)
          brace = find_opening_brace(lines, index)
          next unless brace
          body, _ = body_after_opening_brace(lines, brace[:index], brace[:col])
          return true if body.lines.any?(&.matches?(case_re))
        end
      end

      false
    end

    private def self.swift_method_bodies(content : String, method : String,
                                         parameter_type : String) : Array(NamedTuple(body: String, line: Int32, body_line: Int32))
      bodies = [] of NamedTuple(body: String, line: Int32, body_line: Int32)
      method_re = Regex.new("\\bfunc\\s+#{Regex.escape(method)}\\s*\\(")
      parameter_re = Regex.new(":\\s*#{Regex.escape(parameter_type)}\\b")
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(method_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        signature = lines[index..brace[:index]].join(" ")
        next unless signature.matches?(parameter_re)

        body, body_line = body_after_opening_brace(lines, brace[:index], brace[:col])
        bodies << {body: body, line: index + 1, body_line: body_line}
      end

      bodies
    end

    private def self.swift_case_body(lines : Array(String), case_index : Int32) : Tuple(String, Int32)
      case_line = lines[case_index]
      case_indent = leading_whitespace_width(case_line)
      body_lines = [] of String
      body_line = case_index + 2

      if colon = case_line.index(':')
        after_colon = case_line[(colon + 1)..]? || ""
        unless after_colon.strip.empty?
          body_lines << after_colon
          body_line = case_index + 1
        end
      end

      index = case_index + 1
      while index < lines.size
        line = lines[index]
        stripped = line.strip
        indent = leading_whitespace_width(line)

        break if !stripped.empty? && indent <= case_indent &&
                 (stripped.starts_with?("case ") || stripped.starts_with?("default") || stripped == "}")
        break if !stripped.empty? && indent < case_indent

        body_lines << line
        index += 1
      end

      {body_lines.join("\n"), body_line}
    end

    private def self.leading_whitespace_width(line : String) : Int32
      width = 0
      line.each_char do |char|
        case char
        when ' '
          width += 1
        when '\t'
          width += 4
        else
          break
        end
      end
      width
    end

    private def self.swift_method_body(content : String, name : String) : NamedTuple(body: String, line: Int32, body_line: Int32)?
      lines = content.lines
      method_re = Regex.new("\\bfunc\\s+#{Regex.escape(name)}\\s*\\(")
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(method_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        body, body_line = body_after_opening_brace(lines, brace[:index], brace[:col])
        return {body: body, line: index + 1, body_line: body_line}
      end

      nil
    end

    private def self.local_swift_method_candidate?(name : String) : Bool
      return false unless name.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)

      swift_deep_link_name?(name) || name.downcase.includes?("route")
    end

    private def self.swift_deep_link_name?(name : String) : Bool
      downcased = name.downcase
      downcased.includes?("url") || downcased.includes?("deeplink") ||
        downcased.includes?("deep_link") || downcased.includes?("link")
    end

    private def self.ios_callee_noise?(name : String) : Bool
      return true if IOS_CALLEE_NOISE.includes?(name)
      return true if name.starts_with?("Logger.")
      return true if name.ends_with?(".host")
      return true if name.ends_with?(".path")
      return true if name.ends_with?(".windowUUID")
      return true if name.includes?("queryItems") && name.ends_with?(".first")
      return true if name.includes?("URLContexts") && name.ends_with?(".first")

      false
    end

    # Finds the first `{` at/after the matched line (same line, else within a
    # few lines for a func whose parameter list and/or brace wrap onto their
    # own lines — a folded multi-line signature can run several lines before
    # the body brace).
    private def self.find_opening_brace(lines : Array(String), start : Int32) : NamedTuple(index: Int32, col: Int32)?
      idx = start
      while idx < lines.size && idx <= start + 6
        col = lines[idx].index('{')
        return {index: idx, col: col} if col
        idx += 1
      end
      nil
    end

    # Brace-matched body text starting just after lines[opening_index][col],
    # ignoring braces inside comments/strings. Ported from the Swift analyzers'
    # shared body_after_opening_brace.
    private def self.body_after_opening_brace(lines : Array(String), opening_index : Int32, col : Int32) : Tuple(String, Int32)
      first = lines[opening_index][(col + 1)..]? || ""
      clean, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first, 0, false)
      brace = 1 + clean.count('{') - clean.count('}')
      if brace <= 0
        # Single-line body: trim the closing `}` and anything after it so a
        # trailing `.padding()` etc. doesn't leak into the handler body.
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
  end
end
