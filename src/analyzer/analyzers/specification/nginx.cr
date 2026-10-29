require "../../engines/specification_engine"
require "../../../utils/url_path"

module Analyzer::Specification
  class Nginx < SpecificationEngine
    analyzer_for "nginx"

    METHOD_ANY = "ANY"

    LOCATION_RE     = /^location\s+(?:(=|~\*|~|\^~)\s+)?(\S+)/
    SERVER_NAME_RE  = /^server_name\s+([^;]+);?/
    LISTEN_TLS_RE   = /\bssl\b|\bhttp2\b/
    LISTEN_RE       = /^listen\b/
    METHOD_BLOCK_RE = /^if\s*\(\s*\$request_method\s*=\s*([A-Z]+)\s*\)/
    AUTH_RE         = /\A(auth_basic|auth_request|auth_jwt)\s+(.+)\z/
    ACCESS_RE       = /\A(allow|deny)\s+(\S+)\z/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::NGINX_SPEC) do |path, details|
        content = read_file_content(path)
        process_content(content, details)
      end

      @result
    end

    private class Frame
      getter kind : String
      getter value : String
      getter line : Int32
      getter modifier : String
      getter result_start : Int32?
      property result_end : Int32?
      property? denial_seen : Bool = false
      property? other_effect : Bool = false
      getter parent : Frame?
      # `auth_basic` / `auth_request` / `auth_jwt` set in this block, with
      # the line they are set on; `off` is kept, since it cancels an
      # inherited one.
      getter auth = {} of String => Tuple(String, Int32)
      # `allow` / `deny` in this block, in order: like every array directive,
      # any of them here replaces the whole inherited list.
      getter access = [] of Tuple(String, String, Int32)

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

    private def process_content(content : String, details : Details)
      stack = [] of Frame
      server_names = [] of String
      server_tls = false
      owed = 0
      # The location each row of this file was emitted from, by its index
      # from `base`. Access rules are resolved only after the whole file is
      # read: a server-level `auth_basic` written below its locations still
      # guards them.
      base = @result.size
      owners = [] of Frame

      content.each_line.with_index do |raw, idx|
        line = strip_template_actions(strip_comment(raw)).strip
        next if line.empty?

        # Pre-handle a trailing `}` so we pop the closing frame
        # before processing the rest of the line's directives.
        balanced = line
        while balanced.starts_with?("}")
          pop_frame(stack, owners, base)
          if stack.empty?
            server_names = [] of String
            server_tls = false
          end
          balanced = balanced[1..].strip
          break if balanced.empty?
        end
        next if balanced.empty?

        depth_before = stack.size
        structure = balanced
        directive_line = balanced
        if balanced.matches?(/^server\s*\{/)
          stack << Frame.new("server", "", idx + 1, parent: stack.last?)
          server_names = [] of String
          server_tls = false
        elsif m = SERVER_NAME_RE.match(balanced)
          m[1].split(/\s+/).reject(&.empty?).each { |n| server_names << n }
        elsif balanced.matches?(LISTEN_RE)
          server_tls = true if balanced.matches?(LISTEN_TLS_RE)
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
            emit_location(details, location, modifier, METHOD_ANY, server_names, server_tls, idx + 1)
            frame.result_end = @result.size
            (@result.size - base - owners.size).times { owners << frame }
          end
        elsif m = METHOD_BLOCK_RE.match(balanced)
          method = m[1].upcase
          if loc = current_location(stack)
            emit_location(details, loc.value, loc.modifier, method, server_names, server_tls, idx + 1)
            (@result.size - base - owners.size).times { owners << loc }
          end
        end

        if loc = current_location(stack)
          track_location_effect(loc, directive_line)
        end
        # A line that opens an `if (...) {` or `limit_except` block holds
        # that block's directives, not the enclosing one's.
        opens_block = stack.size == depth_before && structure.count('{') > owed
        if (scope = stack.last?) && scope.access_scope? && !opens_block
          track_access(scope, directive_line, idx + 1)
        end

        # Every `{` opens a frame and every `}` closes one. The handlers above
        # push the frames that mean something; any other `{` gets a
        # placeholder, so `if ($bad_ua) { return 403; }`, an `@named`
        # location or a quoted `'{}'` closes only what it opened. Popping on every `}` without the matching push emptied the
        # stack early: the location lost its later `$request_method` blocks
        # and the server's host/TLS reset mid-block. `owed` covers a location
        # whose `{` sits on the next line.
        net = structure.count('{') - (stack.size - depth_before) - owed
        owed = net < 0 ? -net : 0
        head = balanced.matches?(/\Ahttp\s*\{/) ? "http" : ""
        net.times { stack << Frame.new("block", head, idx + 1, parent: stack.last?) }
        structure.count('}').times { pop_frame(stack, owners, base) }
      end

      owners.each_with_index do |frame, i|
        next unless tag = access_tag(frame, details)
        endpoint = @result[base + i]
        endpoint.add_tag(tag)
        @result[base + i] = endpoint
      end
    end

    private def track_access(frame : Frame, line : String, number : Int32)
      line.gsub(/[{}]/, " ").split(';').each do |statement|
        directive = statement.strip
        if m = AUTH_RE.match(directive)
          frame.auth[m[1]] = {m[2].strip, number}
        elsif m = ACCESS_RE.match(directive)
          frame.access << {m[1], m[2], number}
        end
      end
    end

    # The guard nginx applies to a location: each directive comes from the
    # nearest enclosing block that sets it. `allow ...; deny all;` refuses
    # every other client address. A lone `deny all` admits no caller at all,
    # so it is not read as a guard here (`pop_frame` drops such a location).
    # ponytail: one file at a time; a directive pulled in by `include` from
    # another file is not seen.
    private def access_tag(location : Frame, details : Details) : Tag?
      guards = [] of Tuple(String, Int32)
      {"auth_basic", "auth_request", "auth_jwt"}.each do |name|
        frame = location
        while frame && !frame.auth.has_key?(name)
          frame = frame.parent
        end
        next unless frame
        value, line = frame.auth[name]
        guards << {"#{name} #{value}", line} unless value.delete("\"'") == "off"
      end

      frame = location
      while frame && frame.access.empty?
        frame = frame.parent
      end
      if frame
        rules = frame.access
        # First match wins, so only the rules up to the first `all` count.
        cut = rules.index { |rule| rule[1] == "all" }
        if cut && cut > 0 && rules[cut][0] == "deny"
          guards << {rules[0..cut].join("; ") { |rule| "#{rule[0]} #{rule[1]}" }, rules[0][2]}
        end
      end
      return if guards.empty?

      declared_access_tag("Protected by nginx #{guards.join(", ", &.first)}", details.code_paths.first.path, guards.first[1])
    end

    private def pop_frame(stack : Array(Frame), owners : Array(Frame), base : Int32)
      frame = stack.pop?
      return unless frame
      return unless frame.kind == "location" && frame.denial_seen?
      return if frame.other_effect?

      # Only this location's own rows: a nested location matched on its own
      # does not run the parent's `return`.
      start = frame.result_start
      stop = frame.result_end
      return unless start && stop && stop > start
      @result.delete_at(start...stop)
      owners.delete_at((start - base)...(stop - base))
    end

    private def track_location_effect(location : Frame, line : String)
      line = line.gsub(/\{\{.*?\}\}/, "").gsub(/[{}]/, " ")
      line.split(';').each do |statement|
        directive = statement.strip
        next if directive.empty?

        if directive.matches?(/\Areturn\s+4\d\d(?:\s|$)/i) || directive.matches?(/\Adeny\s+all\z/i)
          location.denial_seen = true
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

    private def emit_location(details : Details, path : String, modifier : String, method : String, hosts : Array(String), tls : Bool, line : Int32)
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
      detail = Details.new(PathInfo.new(details.code_paths.first.path, line))
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
