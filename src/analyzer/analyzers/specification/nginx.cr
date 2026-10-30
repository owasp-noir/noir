require "../../engines/specification_engine"
require "../../../utils/url_path"

module Analyzer::Specification
  class Nginx < SpecificationEngine
    analyzer_for "nginx"

    METHOD_ANY = "ANY"

    # nginx also reads a modifier glued to the URI (`location =/x`,
    # `location ~^/x`).
    LOCATION_RE     = /^location\s+(?:(=|~\*|~|\^~)\s*)?(\S+)/
    INCLUDE_RE      = /^include\s+["']?([^"';\s]+)["']?\s*;/
    SERVER_NAME_RE  = /^server_name\s+([^;]+);?/
    LISTEN_TLS_RE   = /\bssl\b|\bhttp2\b/
    LISTEN_RE       = /^listen\b/
    METHOD_BLOCK_RE = /^if\s*\(\s*\$request_method\s*=\s*([A-Z]+)\s*\)/
    AUTH_RE         = /\A(auth_basic|auth_request|auth_jwt|satisfy)\s+(.+)\z/
    ACCESS_RE       = /\A(allow|deny)\s+(\S+)\z/
    # `${VAR}`: an nginx variable, or an envsubst placeholder. Its braces are
    # not structure.
    ENVSUBST_RE = /\$\{\w+\}/
    BRACE_RE    = /\$\{\w+\}|[{}]/
    # `{{ if }}` / `{{- with }}` ... `{{ end }}` around directives in a
    # `.tmpl` / `.template` file.
    TEMPLATE_OPEN_RE  = /\{\{-?\s*(?:if|with|range)\b/
    TEMPLATE_CLOSE_RE = /\{\{-?\s*end\b/
    SETTING_NOTE      = " (a setting can make it public)"

    # A directive as written in one block. `conditional`: a template action
    # or a variable decides its value, or a template `if` around it decides
    # whether it is there at all.
    record Setting, value : String, path : String, line : Int32, conditional : Bool
    record Rule, verb : String, address : String, path : String, line : Int32, conditional : Bool

    @files = [] of String
    @include_targets = {} of Tuple(String, String) => Array(String)
    @config_roots = {} of String => Array(String)

    # A file `include`d by another is read where the directive sits, with
    # the including block's host, TLS and access rules, and not on its own.
    # Files that only include each other (a cycle no other file reaches) are
    # still read on their own.
    def analyze
      each_spec_file(Noir::LocatorKeys::NGINX_SPEC) { |path| @files << path }
      edges = {} of String => Array(String)
      @files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("include")
        targets = [] of String
        content.each_line do |raw|
          next unless m = INCLUDE_RE.match(strip_template_actions(strip_comment(raw)).strip)
          targets.concat(include_targets(path, m[1]))
        end
        edges[path] = targets unless targets.empty?
      end
      included = edges.values.flatten.to_set
      reached = Set(String).new
      pending = @files.reject { |path| included.includes?(path) }
      while file = pending.pop?
        edges[file]?.try &.each { |target| pending << target if reached.add?(target) }
      end

      each_spec_file(Noir::LocatorKeys::NGINX_SPEC) do |path|
        next if reached.includes?(path)
        state = State.new(@result.size)
        process_file(path, state)
        resolve_access(state)
      end

      @result
    end

    # Locations of an ingress-nginx `server-snippet`, read as if written in
    # the `server` block the controller generates. `first_line`: the line of
    # `path` the snippet starts on.
    def snippet_endpoints(content : String, path : String, first_line : Int32) : Array(Endpoint)
      state = State.new(@result.size)
      state.stack << Frame.new("server", "", first_line)
      process_content(content, path, state, first_line - 1)
      resolve_access(state)
      @result
    end

    GLOB_CHARS = /[\\*?\[\]{}]/

    # The scanned nginx files an `include` names. nginx resolves a relative
    # pattern against its configuration prefix (`/etc/nginx`), which in a
    # repository is the config root (`config_roots`); the including file's
    # own directory and then its parent are tried first
    # (`services/a/conf.d/a.conf` including `snippets/x.conf`). An absolute
    # pattern
    # (`/etc/nginx/conf.d/locations/*.conf`) is matched under the config root
    # by its path suffixes, longest first: `conf.d/locations/*.conf`, then
    # `locations/*.conf`; a lone last segment only when it is no glob
    # (`/etc/nginx/locations.conf`). A pattern that is not a valid glob
    # resolves to nothing.
    private def include_targets(path : String, pattern : String) : Array(String)
      @include_targets[{path, pattern}] ||= begin
        dir = File.dirname(path)
        roots = config_roots(dir)
        found = [] of String
        if pattern.starts_with?('/')
          parts = pattern.split('/').reject(&.empty?)
          parts.each_index do |i|
            suffix = parts[i..].join('/')
            break if i == parts.size - 1 && suffix.matches?(GLOB_CHARS)
            roots.each do |root|
              found = files_under(root, suffix, path)
              break unless found.empty?
            end
            break unless found.empty?
          end
        else
          parent = File.dirname(dir)
          near = parent != dir && within_scan_base?(parent) ? [dir, parent] : [dir]
          (near + roots).uniq.each do |root|
            found = files_under(root, pattern, path)
            break unless found.empty?
          end
        end
        found
      end
    end

    private def files_under(dir : String, pattern : String, includer : String) : Array(String)
      glob = File.join(dir.gsub(GLOB_CHARS) { |c| "\\#{c}" }, pattern)
      @files.select { |file| file != includer && File.match?(glob, file) }.sort!
    rescue File::BadPatternError
      [] of String
    end

    # The directory standing in for nginx's prefix: the nearest one, from
    # the including file's up to the scan base, that holds an `nginx.conf`
    # or is named `nginx` (`deploy/nginx/`, `etc/nginx/`). Without one, the
    # including file's directory and its parent. One app's `app1/nginx.conf`
    # therefore does not bind a `conf.d/` at the repository root.
    private def config_roots(dir : String) : Array(String)
      @config_roots[dir] ||= begin
        current = dir
        found = nil
        while within_scan_base?(current)
          if File.basename(current) == "nginx" || File.exists?(File.join(current, "nginx.conf"))
            found = current
            break
          end
          parent = File.dirname(current)
          break if parent == current
          current = parent
        end
        if found
          [found]
        else
          parent = File.dirname(dir)
          parent != dir && within_scan_base?(parent) ? [dir, parent] : [dir]
        end
      end
    end

    # What a file shares with the files it includes: the open blocks and the
    # server's host and TLS. `owners`: the location each row was emitted
    # from, by its index from `base`.
    private class State
      getter stack = [] of Frame
      property server_names = [] of String
      property? server_tls = false
      getter owners = [] of Frame
      getter base : Int32
      getter reading = [] of String

      def initialize(@base : Int32)
      end
    end

    private class Frame
      getter kind : String
      getter value : String
      getter line : Int32
      getter modifier : String
      getter result_start : Int32?
      property result_end : Int32?
      property? denial_seen : Bool = false
      property? internal : Bool = false
      property? other_effect : Bool = false
      getter parent : Frame?
      # `auth_basic` / `auth_request` / `auth_jwt` / `satisfy` set in this
      # block; `off` is kept, since it cancels an inherited one.
      getter settings = {} of String => Setting
      # `allow` / `deny` in this block, in order: like every array directive,
      # any of them here replaces the whole inherited list.
      getter access = [] of Rule

      def initialize(@kind : String, @value : String, @line : Int32, @modifier : String = "", @result_start : Int32? = nil, @parent : Frame? = nil)
      end

      # Only the blocks nginx inherits these directives through. An `if` or
      # `limit_except` placeholder does not guard its whole location.
      # ponytail: `limit_except GET { auth_basic ...; }` (guards the other
      # verbs only) is not modelled.
      def access_scope? : Bool
        kind == "location" || kind == "server" || value == "http"
      end
    end

    private def process_file(path : String, state : State)
      return if state.reading.includes?(path)
      state.reading << path
      process_content(read_file_content(path), path, state)
      state.reading.pop
    end

    private def process_content(content : String, path : String, state : State, line_offset : Int32 = 0)
      stack = state.stack
      owners = state.owners
      base = state.base
      owed = 0
      template_depth = 0

      content.each_line.with_index(line_offset) do |raw, idx|
        uncommented = strip_comment(raw)
        templated = uncommented.includes?("{{")
        conditional = template_depth > 0 || templated
        if templated
          template_depth = Math.max(0, template_depth + uncommented.scan(TEMPLATE_OPEN_RE).size - uncommented.scan(TEMPLATE_CLOSE_RE).size)
        end
        line = strip_template_actions(uncommented).strip
        next if line.empty?

        # Pre-handle a trailing `}` so we pop the closing frame
        # before processing the rest of the line's directives.
        balanced = line
        while balanced.starts_with?("}")
          pop_frame(stack, owners, base)
          if stack.empty?
            state.server_names = [] of String
            state.server_tls = false
          end
          balanced = balanced[1..].strip
          break if balanced.empty?
        end
        next if balanced.empty?

        depth_before = stack.size
        structure = balanced
        directive_line = balanced
        if balanced.matches?(/^server\s*(?:\{|\z)/)
          stack << Frame.new("server", "", idx + 1, parent: stack.last?)
          state.server_names = [] of String
          state.server_tls = false
        elsif m = SERVER_NAME_RE.match(balanced)
          # `_` and `""` are the conventional catch-all names, not hosts.
          m[1].split(/\s+/).each { |n| state.server_names << n unless n.in?("", "_", %(""), "''") }
        elsif balanced.matches?(LISTEN_RE)
          state.server_tls = true if balanced.matches?(LISTEN_TLS_RE)
        elsif m = INCLUDE_RE.match(balanced)
          include_targets(path, m[1]).each { |target| process_file(target, state) }
        elsif balanced.matches?(/^http\s*(?:\{|\z)/)
          stack << Frame.new("block", "http", idx + 1, parent: stack.last?)
        elsif m = LOCATION_RE.match(balanced)
          modifier = m[1]? || ""
          raw_location = m[2]
          location = normalize_location_path(raw_location)
          # The path's own braces (`^/v\d{1,2}/u$`) are not structure; only
          # what follows it, plus a `{` glued to its end, opens a block.
          structure = "#{'{' if raw_location.ends_with?('{')}#{balanced[m.end(0)..]}"
          directive_line = structure
          unless location.empty? || internal_location?(raw_location) || internal_location?(location)
            frame = Frame.new("location", location, idx + 1, modifier, @result.size, stack.last?)
            stack << frame
            emit_location(path, location, modifier, METHOD_ANY, state.server_names, state.server_tls?, idx + 1)
            frame.result_end = @result.size
            (@result.size - base - owners.size).times { owners << frame }
          end
        elsif m = METHOD_BLOCK_RE.match(balanced)
          method = m[1].upcase
          if loc = current_location(stack)
            emit_location(path, loc.value, loc.modifier, method, state.server_names, state.server_tls?, idx + 1)
            (@result.size - base - owners.size).times { owners << loc }
          end
        end

        if loc = current_location(stack)
          track_location_effect(loc, directive_line, conditional)
        end
        # A line that opens an `if (...) {` or `limit_except` block holds
        # that block's directives, not the enclosing one's.
        opens_block = stack.size == depth_before && structure.gsub(ENVSUBST_RE, "").count('{') > owed
        if (scope = stack.last?) && scope.access_scope? && !opens_block
          track_access(scope, directive_line, path, idx + 1, conditional, templated)
        end

        # Every `{` opens a frame and every `}` closes one. The handlers above
        # push the frames that mean something; any other `{` gets a
        # placeholder, so `if ($bad_ua) { return 403; }`, an `@named`
        # location or a quoted `'{}'` closes only what it opened. Popping on every `}` without the matching push emptied the
        # stack early: the location lost its later `$request_method` blocks
        # and the server's host/TLS reset mid-block. `owed` covers a location
        # (or `server` / `http` block) whose `{` sits on the next line.
        net = structure.count('{') - (stack.size - depth_before) - owed
        owed = net < 0 ? -net : 0
        net.times { stack << Frame.new("block", "", idx + 1, parent: stack.last?) }
        structure.count('}').times { pop_frame(stack, owners, base) }
      end
    end

    # Access rules are resolved only after the whole file is read: a
    # server-level `auth_basic` written below its locations still guards them.
    private def resolve_access(state : State)
      state.owners.each_with_index do |frame, i|
        next unless tag = access_tag(frame)
        endpoint = @result[state.base + i]
        endpoint.add_tag(tag)
        @result[state.base + i] = endpoint
      end
    end

    # `templated`: a template action sat on this line, so the value left
    # after stripping it is not what nginx reads and is not shown; a literal
    # `off` is still an `off`.
    private def track_access(frame : Frame, line : String, path : String, number : Int32, conditional : Bool, templated : Bool)
      line.gsub(BRACE_RE) { |token| token.size > 1 ? token : " " }.split(';').each do |statement|
        directive = statement.strip
        if m = AUTH_RE.match(directive)
          value = m[2].strip
          value = "" if templated && !off?(value)
          # A variable's value is configuration: a `map` can make it `off`.
          frame.settings[m[1]] = Setting.new(value, path, number, conditional || value.includes?('$'))
        elsif m = ACCESS_RE.match(directive)
          frame.access << Rule.new(m[1], m[2], path, number, conditional)
        end
      end
    end

    # The setting a location inherits: the nearest enclosing block that sets
    # it. A conditional `off` may not be there, so then the inherited value
    # still applies, on a setting.
    private def effective_setting(frame : Frame?, name : String) : Setting?
      while frame
        if setting = frame.settings[name]?
          return setting unless setting.conditional && off?(setting.value)
          return effective_setting(frame.parent, name).try(&.copy_with(conditional: true))
        end
        frame = frame.parent
      end
    end

    private def off?(value : String) : Bool
      value.delete("\"'") == "off"
    end

    # The guard nginx applies to a location: each directive comes from the
    # nearest enclosing block that sets it. `allow ...; deny all;` refuses
    # every other client address. A lone `deny all` admits no caller at all,
    # so it is not read as a guard here (`pop_frame` drops such a location).
    #
    # Under `satisfy all` (the default) a caller must pass every check; under
    # `satisfy any` one is enough, so an access list that admits every
    # address (`allow all`) opens the location whatever auth it also has.
    # That is the usual way to open a sub-location of an `auth_basic` server.
    # ponytail: an included file that holds only directives (`auth_basic` in
    # a `snippets/auth.conf` with no `location`) is not an nginx file to the
    # detector, so its guard is not seen.
    private def access_tag(location : Frame) : Tag?
      guards = [] of Setting
      {"auth_basic", "auth_request", "auth_jwt"}.each do |name|
        next unless setting = effective_setting(location, name)
        next if off?(setting.value)
        shown = setting.value.empty? ? name : "#{name} #{setting.value}"
        guards << setting.copy_with(value: shown)
      end

      frame = location
      while frame && frame.access.empty?
        frame = frame.parent
      end
      any = effective_setting(location, "satisfy").try(&.value) == "any"
      if frame
        rules = frame.access
        # First match wins, so only the rules up to the first `all` count.
        cut = rules.index { |rule| rule.address == "all" }
        if cut && rules[cut].verb == "allow"
          return if any
        elsif cut && cut > 0
          used = rules[0..cut]
          guards << Setting.new(used.join("; ") { |rule| "#{rule.verb} #{rule.address}" }, used[0].path, used[0].line, used.any?(&.conditional))
        end
      end
      return if guards.empty?

      # Any one guard is enough to pass under `satisfy any`, so one a setting
      # decides opens the location; under `all` every one has to be lifted.
      conditional = any ? guards.any?(&.conditional) : guards.all?(&.conditional)
      description = "Protected by nginx #{guards.join(any ? " or " : ", ", &.value)}#{SETTING_NOTE if conditional}"
      declared_access_tag(description, guards.first.path, guards.first.line)
    end

    private def pop_frame(stack : Array(Frame), owners : Array(Frame), base : Int32)
      frame = stack.pop?
      return unless frame
      return unless frame.kind == "location"
      return drop_rows(frame, owners, base) if frame.internal?
      return unless frame.denial_seen?
      return if frame.other_effect?

      # Only this location's own rows: a nested location matched on its own
      # does not run the parent's `return`.
      start = frame.result_start
      stop = frame.result_end
      return unless start && stop && stop > start
      @result.delete_at(start...stop)
      owners.delete_at((start - base)...(stop - base))
    end

    # An `internal` location answers only nginx's own redirects
    # (`auth_request`, `X-Accel-Redirect`, `error_page`); a client request
    # gets a 404. Its `$request_method` rows go with it, a nested location's
    # do not.
    private def drop_rows(frame : Frame, owners : Array(Frame), base : Int32)
      return unless start = frame.result_start
      (owners.size - 1).downto(start - base) do |i|
        next unless owners[i].same?(frame)
        owners.delete_at(i)
        @result.delete_at(base + i)
      end
    end

    # `conditional`: a template decides whether the line is there, so an
    # `internal` on it may not be.
    private def track_location_effect(location : Frame, line : String, conditional : Bool)
      line = line.gsub(/\{\{.*?\}\}/, "").gsub(/[{}]/, " ")
      line.split(';').each do |statement|
        directive = statement.strip
        next if directive.empty?

        if directive.matches?(/\Areturn\s+4\d\d(?:\s|$)/i) || directive.matches?(/\Adeny\s+all\z/i)
          location.denial_seen = true
        elsif directive == "internal"
          location.internal = true unless conditional
        else
          # Conditional returns and other directives may still serve content.
          location.other_effect = true
        end
      end
    end

    private def current_location(stack : Array(Frame)) : Frame?
      stack.reverse_each { |f| return f if f.kind == "location" }
    end

    private def strip_comment(line : String) : String
      previous = '\0'
      line.each_char_with_index do |ch, idx|
        if ch == '#' && (idx == 0 || previous.whitespace? || previous.in?(';', '{', '}'))
          return line[0...idx]
        end
        previous = ch
      end
      line
    end

    private def strip_template_actions(line : String) : String
      line.gsub(/\{\{.*?\}\}/, "")
    end

    private def normalize_location_path(path : String) : String
      path = path.gsub(/[{};]\z/, "")
      if path.size >= 2 && ((path.starts_with?('"') && path.ends_with?('"')) ||
         (path.starts_with?('\'') && path.ends_with?('\'')))
        path = path[1..-2]
      end
      path
    end

    private def internal_location?(path : String) : Bool
      path.starts_with?("@") || path.includes?("{{") || path.includes?("}}")
    end

    private def emit_location(file : String, path : String, modifier : String, method : String, hosts : Array(String), tls : Bool, line : Int32)
      return if path.empty?

      path_type = case modifier
                  when "="  then "exact"
                  when "~"  then "regex"
                  when "~*" then "regex-i"
                  when "^~" then "prefix-stop"
                  else           "prefix"
                  end

      regex = path_type.starts_with?("regex") && Noir::URLPath.regex_route?(path)
      path = Noir::URLPath.strip_regex_anchors(path) if path_type.starts_with?("regex")
      detail = Details.new(PathInfo.new(file, line))
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, method, detail)
        endpoint.kind = "regex" if regex
        endpoint.add_tag(Tag.new("nginx-path-type", path_type, "nginx_analyzer"))
        endpoint.add_tag(Tag.new("nginx-host", host, "nginx_analyzer")) unless host.empty?
        endpoint.protocol = "https" if tls
        @result << endpoint
      end
    end
  end
end
