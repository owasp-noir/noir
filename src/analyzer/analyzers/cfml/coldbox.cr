require "../../engines/cfml_engine"

module Analyzer::Cfml
  # ColdBox routing.
  #
  # Routes are declared in a dedicated `config/Router.cfc` (or the legacy
  # `config/routes.cfm`), which makes them the closest CFML analogue of a
  # Rails or Laravel route file:
  #
  #     route( "/", "echo.index" );
  #     post( "/login", "auth.login" );
  #     get( "/sites/:slug/settings", "siteSettings.index" );
  #     resources( resource = "authors", except = "new,edit" );
  #     route( "/render/:format" ).to( "actionRendering.index" );
  #
  # Two pieces of context live outside the router and are resolved here,
  # because without them the emitted URLs and verbs are wrong:
  #
  #   * a module's routes are mounted under its `ModuleConfig.cfc`
  #     `entryPoint`, so ContentBox's API routes are `/cbapi/v1/login`
  #     rather than `/login`;
  #   * a bare `route()` accepts any verb, but the handler constrains it
  #     via `this.allowedMethods`, so that map decides the verbs instead
  #     of fanning out to all seven.
  class Coldbox < CfmlEngine
    analyzer_for "cfml_coldbox"

    ROUTER_FILES = Set{"router.cfc", "routes.cfm"}

    # `route()` is verb-agnostic; the rest name their verb.
    ROUTE_CALL_RE = /(?<![\w.])(route|get|post|put|patch|delete|head|options)\s*\(/i
    RESOURCES_RE  = /(?<![\w.])resources\s*\(/i

    # Legacy tag-syntax registration, still present in older configs.
    ADD_ROUTE_RE = /(?<![\w.])addRoute\s*\(/i

    # `group( { pattern : "/api" }, function( options ){ ... } )` prefixes
    # every route declared inside the closure, and groups nest. Ignoring
    # them is both a false positive and a false negative at once: ColdBox's
    # own test harness declares `route( "/:user_id" )` inside
    # `group( { pattern : "/runAWNsync" ... } )`, which was reported as
    # `/:user_id` — a URL that answers nothing — while the real
    # `/runAWNsync/:user_id` went unreported.
    GROUP_CALL_RE = /(?<![\w.])group\s*\(/i

    # A group may name a namespace instead of a path. Namespaces are not
    # paths in themselves: they become reachable only where a route mounts
    # them, so the mount pattern is what supplies the prefix.
    NAMESPACE_MOUNT_RE = /\.\s*toNamespaceRouting\s*\(\s*["']([^"']+)["']/i
    ADD_NAMESPACE_RE   = /(?<![\w.])addNamespace\s*\(/i

    # `route( "/luis" ).toNamespaceRouting( "luis" )` — the mount pattern
    # and the namespace it carries, in one statement.
    NAMESPACE_ROUTE_RE = /(?<![\w.])route\s*\(\s*["']([^"']+)["']\s*\)\s*\.\s*toNamespaceRouting\s*\(\s*["']([^"']+)["']\s*\)/i

    # Chained builders that follow `route( ... )` up to the statement end.
    CHAINED_VERBS_RE = /\.\s*withVerbs\s*\(\s*["']([^"']+)["']/i
    CHAIN_LIMIT      = 400

    # `route( "/x" ).withAction( { get : "show", post : "save" } )` binds
    # one action per verb, so the struct's keys *are* the verbs the route
    # answers. Without this a `route()` carrying only a `withAction` map
    # fell back to GET — ColdBox's own harness registers `/invalid-restful`
    # and `/invalid-main-method` as POST that way.
    CHAINED_ACTIONS_RE = /\.\s*withAction\s*\(\s*\{([^}]*)\}/i
    ACTION_VERB_RE     = /["']?(\w+)["']?\s*[:=]/

    # `var sitePrefix = "/sites/:site"` — referenced as `#siteprefix#`,
    # case-insensitively.
    LOCAL_STRING_RE  = /(?:var\s+)?([A-Za-z_]\w*)\s*=\s*["']([^"'#]*)["']\s*;/
    INTERPOLATION_RE = /#\s*([A-Za-z_]\w*)\s*#/

    # `this.allowedMethods = { index : "GET", create : "POST,PUT" }`
    ALLOWED_METHODS_BLOCK_RE = /this\s*\.\s*allowedMethods\s*=\s*\{([^}]*)\}/i
    ALLOWED_METHODS_ENTRY_RE = /["']?(\w+)["']?\s*:\s*["']([^"']*)["']/
    # `function show( event, rc, prc ) allowedMethods="GET"{`
    FUNCTION_ALLOWED_RE = /(?<![\w.])function\s+(\w+)\s*\([^)]*\)[^{;]*?allowedMethods\s*=\s*["']([^"']+)["']/i

    # Placeholders carry inline constraints in three shapes, and all of
    # them must be stripped or the quantifier leaks into the URL:
    #   `:id-numeric{2}`  `:name-regex(luis)`  `:name{4}`
    # The parameter is `id` / `name`; everything from the first `-`, `{`
    # or `(` to the end of the segment is the constraint.
    PLACEHOLDER_RE = /:([A-Za-z_]\w*)(?:[-{(][^\/]*)?/

    # ColdBox's standard resource expansion.
    RESOURCE_ROUTES = [
      {"index", "GET", ""},
      {"new", "GET", "/new"},
      {"create", "POST", ""},
      {"show", "GET", "/:id"},
      {"edit", "GET", "/:id/edit"},
      {"update", "PUT", "/:id"},
      {"delete", "DELETE", "/:id"},
    ]

    @allowed_methods : Hash(String, Hash(String, Array(String)))? = nil
    @namespace_mounts : Hash(String, String)? = nil

    def analyze
      routers = router_files
      return @result if routers.empty?

      # Both indexes are built once from every router/handler in the scan;
      # worker fibers must not race to populate them.
      allowed_methods
      @namespace_mounts = build_namespace_mounts(routers)

      parallel_analyze(routers) do |path|
        analyze_router(path)
      end

      @result
    end

    private def router_files : Array(String)
      cfml_components.select { |path| router_file?(path) } +
        cfml_pages.select { |path| router_file?(path) }
    end

    private def router_file?(path : String) : Bool
      ROUTER_FILES.includes?(File.basename(path).downcase)
    end

    private def analyze_router(path : String)
      content = strip_all_comments(read_file_content(path))
      prefix = module_prefix(path)
      locals = local_strings(content)
      groups = group_blocks(content, locals)

      extract_routes(content, path, prefix, locals, groups)
      extract_resources(content, path, prefix, locals, groups)
    end

    private def extract_routes(content : String, path : String, prefix : String,
                               locals : Hash(String, String), groups : Array(Group))
      {ROUTE_CALL_RE, ADD_ROUTE_RE}.each do |pattern|
        content.scan(pattern) do |match|
          start = match.begin(0) || 0
          next unless statement_start?(content, start)

          verb = match.size > 1 ? match[1].downcase : "route"

          open_paren = content.index('(', start)
          next unless open_paren

          close_paren = matching_paren(content, open_paren)
          next unless close_paren

          arguments = call_arguments(content[(open_paren + 1)...close_paren], locals)
          pattern_value = arguments["pattern"]? || arguments["0"]?
          next if pattern_value.nil? || pattern_value.empty?

          resolved = interpolate(pattern_value, locals)
          next unless resolved

          scoped = scoped_prefix(prefix, groups, start)
          next unless scoped

          url = build_url(scoped, resolved)
          next if url.empty?

          target = arguments["target"]? || arguments["1"]?
          chain = statement_chain(content, close_paren + 1)
          # `route( "/luis" ).toNamespaceRouting( "luis" )` mounts a
          # namespace at that pattern; it is not itself requestable, and
          # the routes it exposes are emitted under the mount instead.
          next if chain.matches?(NAMESPACE_MOUNT_RE)

          target ||= chained_target(chain)

          route_verbs(verb, chain, target).each do |method|
            @result << Endpoint.new(url, method, [] of Param,
              Details.new(PathInfo.new(path, line_number_for_index(content, start))))
          end
        end
      end
    end

    private def extract_resources(content : String, path : String, prefix : String,
                                  locals : Hash(String, String), groups : Array(Group))
      content.scan(RESOURCES_RE) do |match|
        start = match.begin(0) || 0
        next unless statement_start?(content, start)

        open_paren = content.index('(', start)
        next unless open_paren

        close_paren = matching_paren(content, open_paren)
        next unless close_paren

        scoped = scoped_prefix(prefix, groups, start)
        next unless scoped

        arguments = call_arguments(content[(open_paren + 1)...close_paren], locals)
        resource = arguments["resource"]? || arguments["0"]?
        next if resource.nil? || resource.empty?

        base = interpolate(arguments["pattern"]? || "/#{resource}", locals)
        next unless base

        # `except` names the actions to drop. A value that resolves to
        # neither a literal nor a declared local is unresolvable, so
        # nothing is dropped rather than guessing.
        excluded = (arguments["except"]? || "").split(',').map(&.strip.downcase).reject(&.empty?).to_set
        only = (arguments["only"]? || "").split(',').map(&.strip.downcase).reject(&.empty?).to_set

        details = Details.new(PathInfo.new(path, line_number_for_index(content, start)))

        RESOURCE_ROUTES.each do |action, method, suffix|
          next if excluded.includes?(action)
          next if !only.empty? && !only.includes?(action)

          url = build_url(scoped, "#{base}#{suffix}")
          next if url.empty?

          @result << Endpoint.new(url, method, [] of Param, details)
          # ColdBox registers PATCH alongside PUT for the update action.
          @result << Endpoint.new(url, "PATCH", [] of Param, details) if action == "update"
        end
      end
    end

    # A `group( options, closure )` call: the character range its closure
    # occupies, and the path segment it contributes. A `nil` prefix means
    # the group scopes its routes somewhere this scan cannot resolve, so
    # the routes inside are dropped rather than reported at the root.
    private record Group, start : Int32, stop : Int32, prefix : String?

    private def group_blocks(content : String, locals : Hash(String, String)) : Array(Group)
      groups = [] of Group

      content.scan(GROUP_CALL_RE) do |match|
        start = match.begin(0) || 0
        next unless statement_start?(content, start)

        open_paren = content.index('(', start)
        next unless open_paren

        close_paren = matching_paren(content, open_paren)
        next unless close_paren

        groups << Group.new(open_paren, close_paren,
          group_prefix(content, open_paren, close_paren, locals))
      end

      groups
    end

    # The group's options struct is its first argument.
    private def group_prefix(content : String, open_paren : Int32, close_paren : Int32,
                             locals : Hash(String, String)) : String?
      open_brace = content.index('{', open_paren)
      # No options struct at all: the group only wraps the closure, so it
      # contributes nothing to the path.
      return "" if open_brace.nil? || open_brace > close_paren

      close_brace = matching_brace(content, open_brace)
      return "" if close_brace.nil? || close_brace > close_paren

      options = call_arguments(content[(open_brace + 1)...close_brace], locals)

      if pattern = options["pattern"]?
        resolved = interpolate(pattern, locals)
        return resolved.nil? ? nil : "/#{resolved.strip.strip('/')}"
      end

      if namespace = options["namespace"]?
        # A namespace is reachable only where a route mounts it. With no
        # mount in the scan there is no URL to report.
        return namespace_mounts[namespace.downcase]?
      end

      # `{ handler : "x", action : "y" }` only retargets; the path is
      # whatever the routes inside declare.
      ""
    end

    # Path prefix in force at `index`: the module entry point plus every
    # enclosing group, outermost first (groups are collected in source
    # order, which is the same thing).
    private def scoped_prefix(base : String, groups : Array(Group), index : Int32) : String?
      return base if groups.empty?

      prefix = base
      groups.each do |group|
        next unless index > group.start && index < group.stop
        segment = group.prefix
        return unless segment

        prefix = "#{prefix}#{segment}"
      end
      prefix
    end

    # namespace name => the path a route mounts it at, across every router
    # in the scan (a module may mount a namespace another module declares).
    private def namespace_mounts : Hash(String, String)
      @namespace_mounts ||= build_namespace_mounts(router_files)
    end

    private def build_namespace_mounts(routers : Array(String)) : Hash(String, String)
      mounts = {} of String => String

      routers.each do |path|
        content = strip_all_comments(read_file_content(path))
        collect_namespace_mounts(content, mounts)
      rescue e
        logger.debug "Error reading namespace mounts from #{path}: #{e}"
      end

      mounts
    end

    private def collect_namespace_mounts(content : String, mounts : Hash(String, String))
      content.scan(NAMESPACE_ROUTE_RE) do |match|
        mounts[match[2].downcase] = "/#{match[1].strip.strip('/')}"
      end

      # `addNamespace( pattern = "/luis", namespace = "luis" )`
      content.scan(ADD_NAMESPACE_RE) do |match|
        start = match.begin(0) || 0
        next unless statement_start?(content, start)

        open_paren = content.index('(', start)
        next unless open_paren

        close_paren = matching_paren(content, open_paren)
        next unless close_paren

        arguments = call_arguments(content[(open_paren + 1)...close_paren])
        pattern = arguments["pattern"]? || arguments["0"]?
        namespace = arguments["namespace"]? || arguments["1"]?
        next if pattern.nil? || namespace.nil? || namespace.empty?

        mounts[namespace.downcase] = "/#{pattern.strip.strip('/')}"
      end
    end

    # The builder chain attached to a route call, bounded by the end of the
    # statement: a `;`, or a line break not continued by a `.`.
    #
    # The bound is load-bearing. A fixed character window ran past the call
    # into whatever followed, so a bare `route()` could inherit the `.to()`
    # of a later statement — and once `toNamespaceRouting` became a
    # suppression signal, three unrelated routes declared above ColdBox's
    # namespace mount disappeared with it.
    private def statement_chain(content : String, from : Int32) : String
      window = content[from, CHAIN_LIMIT]? || ""
      cut = window.size
      after_newline = false

      window.each_char_with_index do |char, index|
        if char == ';'
          cut = index
          break
        end

        if after_newline
          next if char.whitespace?

          # A chain continues with `.`; anything else opens a new statement.
          unless char == '.'
            cut = index
            break
          end
          after_newline = false
        elsif char == '\n'
          after_newline = true
        end
      end

      window[0, cut]
    end

    # `route( "/x" ).to( "handler.action" )` and friends. Every `to*`
    # builder terminates a real route, so the specific one only matters
    # for resolving the handler's allowed methods.
    private def chained_target(chain : String) : String?
      match = chain.match(/\.\s*to(?:Handler)?\s*\(\s*["']([^"']+)["']/i)
      match ? match[1] : nil
    end

    # An explicit verb call wins, then `withVerbs()`, then the target
    # handler's `this.allowedMethods`. A bare `route()` with no resolvable
    # constraint stays GET rather than fanning out to all seven verbs and
    # claiming methods the handler rejects.
    private def route_verbs(verb : String, chain : String, target : String?) : Array(String)
      return [verb.upcase] if HTTP_VERBS.includes?(verb.upcase)

      if match = chain.match(CHAINED_VERBS_RE)
        verbs = split_verbs(match[1])
        return verbs unless verbs.empty?
      end

      if match = chain.match(CHAINED_ACTIONS_RE)
        verbs = action_verbs(match[1])
        return verbs unless verbs.empty?
      end

      if target
        verbs = allowed_for(target)
        return verbs unless verbs.empty?
      end

      ["GET"]
    end

    private def action_verbs(raw : String) : Array(String)
      verbs = [] of String
      raw.scan(ACTION_VERB_RE) do |entry|
        verb = entry[1].upcase
        verbs << verb if HTTP_VERBS.includes?(verb)
      end
      verbs.uniq!
    end

    private def split_verbs(raw : String) : Array(String)
      raw.split(',').compact_map do |verb|
        normalized = verb.strip.upcase
        HTTP_VERBS.includes?(normalized) ? normalized : nil
      end.uniq!
    end

    private def allowed_for(target : String) : Array(String)
      handler, _, action = target.rpartition('.')
      return [] of String if handler.empty? || action.empty?

      actions = allowed_methods[handler.downcase]?
      return [] of String unless actions

      actions[action.downcase]? || [] of String
    end

    # handler name (dotted, as written in the route target) => action =>
    # verbs, from `this.allowedMethods` and per-function attributes.
    private def allowed_methods : Hash(String, Hash(String, Array(String)))
      @allowed_methods ||= begin
        index = {} of String => Hash(String, Array(String))

        cfml_components.each do |path|
          key = handler_key(path)
          next unless key

          content = strip_all_comments(read_file_content(path))
          actions = {} of String => Array(String)

          if match = content.match(ALLOWED_METHODS_BLOCK_RE)
            match[1].scan(ALLOWED_METHODS_ENTRY_RE) do |entry|
              verbs = split_verbs(entry[2])
              actions[entry[1].downcase] = verbs unless verbs.empty?
            end
          end

          content.scan(FUNCTION_ALLOWED_RE) do |entry|
            verbs = split_verbs(entry[2])
            actions[entry[1].downcase] = verbs unless verbs.empty?
          end

          index[key] = actions unless actions.empty?
        rescue e
          logger.debug "Error reading handler #{path}: #{e}"
        end

        index
      end
    end

    # `handlers/api/photos.cfc` is targeted as `api.photos`.
    private def handler_key(path : String) : String?
      normalized = path.gsub(File::SEPARATOR, "/")
      marker = normalized.rindex("/handlers/")
      return unless marker

      relative = normalized[(marker + "/handlers/".size)..]
      relative = relative.sub(/\.cfc\z/i, "")
      return if relative.empty?

      relative.gsub("/", ".").downcase
    end

    # A module's routes mount under its `ModuleConfig.cfc` `entryPoint`.
    # The nearest ancestor wins: ContentBox's nested API module declares
    # the complete `/cbapi/v1`, so walking further up and joining would
    # prepend the parent's entry point twice over.
    private def module_prefix(path : String) : String
      directory = File.dirname(path)
      root = configured_base_for(path)

      while directory.starts_with?(root) && directory.size >= root.size
        config = File.join(directory, "ModuleConfig.cfc")
        if entry = module_entry_point(config)
          return entry
        end

        parent = File.dirname(directory)
        break if parent == directory

        directory = parent
      end

      ""
    end

    private def module_entry_point(config : String) : String?
      return unless File.exists?(config)

      content = read_file_content(config)
      match = content.match(/this\s*\.\s*entryPoint\s*=\s*["']([^"']+)["']/i)
      return unless match

      entry = match[1].strip.strip('/')
      entry.empty? ? nil : "/#{entry}"
    rescue
      nil
    end

    # A pattern whose prefix is computed at runtime cannot be reported as
    # a URL. Substituting an empty string for the unknown would emit a
    # shortened path that does not exist, so the route is skipped instead.
    private def interpolate(value : String, locals : Hash(String, String)) : String?
      return value unless value.includes?('#')

      resolved = true
      substituted = value.gsub(INTERPOLATION_RE) do
        replacement = locals[$~[1].downcase]?
        resolved = false if replacement.nil?
        replacement || ""
      end

      resolved ? substituted : nil
    end

    private def local_strings(content : String) : Hash(String, String)
      locals = {} of String => String
      content.scan(LOCAL_STRING_RE) do |match|
        locals[match[1].downcase] = match[2]
      end
      locals
    end

    private def build_url(prefix : String, pattern : String) : String
      normalized = normalize_placeholders(pattern.strip)
      return "" if normalized.empty?

      combined = "#{prefix}/#{normalized.lstrip('/')}"
      combined = combined.gsub(/\/+/, "/")
      combined = combined.chomp('/') if combined.size > 1
      combined.starts_with?("/") ? combined : "/#{combined}"
    end

    # Drop inline constraints so `:postID-regex:([a-zA-Z]+?)` reports the
    # parameter as `postID`, and drop the optional marker.
    private def normalize_placeholders(pattern : String) : String
      pattern.gsub(PLACEHOLDER_RE) { ":#{$~[1]}" }.gsub("?", "")
    end
  end
end
