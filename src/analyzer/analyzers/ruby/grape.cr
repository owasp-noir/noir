require "../../engines/ruby_engine"
require "../../../utils/ruby_inflector"

module Analyzer::Ruby
  class Grape < RubyEngine
    analyzer_for "ruby_grape"

    GRAPE_VERBS = ["get", "post", "put", "delete", "patch", "head", "options"]

    # `build_grape_index`'s whole-tree pre-pass gate OR-ed two
    # String#includes? scans over every file's content as a standalone
    # boolean gate. Folded into one precompiled union so it costs a single
    # PCRE2 match instead of up to two naive substring scans per file.
    GRAPE_OR_MOUNT_MARKER_RE = Regex.union("Grape", "mount ", "ActiveSupport::Concern")

    # Crystal recompiles an interpolated regex literal (`/^#{verb}.../`)
    # on every evaluation — ~11000x slower than a precompiled one — so
    # matching the verb DSL inside the per-line loop used to recompile
    # 14 regexes for every line of every Grape file. Build the per-verb
    # patterns once at load time instead. `_WITH_PATH` matches
    # `get '/users' do` (capturing the path literal/symbol) and the
    # path-less `get urgency: :low do` (options only); `_BARE_DO` matches
    # the path-less `get do` form.
    GRAPE_VERB_WITH_PATH = GRAPE_VERBS.to_h do |verb|
      {verb, /^#{verb}\b(?:\s+('[^']*'|"[^"]*"|:[^\s,]+))?(?:\s*,[^#]*?|\s+\w+:\s[^#]*?)?\s*do\b/}
    end

    # A route or prefix statement whose options continue on the next line
    # (`namespace 'conans/:name',` / `requirements: {...} do`).
    GRAPE_CONTINUED_DSL = /^(?:resource|resources|namespace|group|segment|route_param|#{GRAPE_VERBS.join('|')})\b/
    MAX_CONTINUATION    = 8

    GRAPE_PREFIX_LITERAL = /^(?:resource|resources|namespace|group|segment)\s+['":]([\w\/\-:]+)[\'""]?(?:\s*,[^#]*?)?\s*do\b/
    # `resource source_type.pluralize do` outside a static loop: the name is
    # only known at runtime, so the segment becomes a `{source_type}`
    # placeholder instead of vanishing from the path.
    GRAPE_PREFIX_EXPR = /^(?:resource|resources|namespace|group|segment)\s+([a-z_]\w*)(?:\.\w+[!?]?)*(?:\s*,[^#]*?)?\s*do\b/
    GRAPE_INCLUDE     = /^include\s+((?:::)?[A-Z][\w:]*)\s*$/
    GRAPE_CONCERN_EXT = /^\s*extend\s+(?:::)?ActiveSupport::Concern\b/
    GRAPE_MODULE_DEF  = /^\s*module\s+([A-Z][\w:]*)/

    # `%w[a b].each do |x|`, `[:a, :b].each do |x|` and
    # `{ "a" => 1, "b" => 2 }.each do |x, y|` over a literal receiver.
    GRAPE_LOOP_OPENER = /^\s*(%[wi][\[\(\{][^\]\)\}]*[\]\)\}]|\[[^\]]*\]|\{.*\})\s*\.each(?:_with_index)?\s+do\s*\|\s*([a-z_]\w*)[^|]*\|\s*$/
    # Unrolling is multiplicative and noir scans untrusted repos, so it is
    # bounded (real Grape loops are a handful of literals, one level deep).
    MAX_LOOP_DEPTH     =      2
    MAX_LOOP_VALUES    =     50
    MAX_LOOP_OUTPUT    = 20_000
    GRAPE_VERB_BARE_DO = GRAPE_VERBS.to_h do |verb|
      {verb, /^#{verb}\s+do\b/}
    end

    @grape_concerns = {} of String => String
    @used_concerns = Set(String).new
    @used_concerns_mutex = Mutex.new

    def analyze
      include_callee = callees_needed?

      # Real Grape apps almost always share config/helpers through a custom
      # base class (`class Base < Grape::API`, then `class Users < API::Base`)
      # and aggregate sub-APIs with `mount`, declaring the global `prefix`
      # and path `version` only on the root aggregator. Gating each file on a
      # literal `Grape::API` mention therefore skipped the vast majority of
      # route files (GitLab: 148 of 157 `lib/api/*.rb` inherit from
      # `::API::Base` and never name `Grape::API`), and the recovered routes
      # would lack their `/api/v4` mount prefix. Build a cross-file index of
      # Grape classes + the prefix each one inherits through the mount graph.
      index = build_grape_index
      @grape_concerns = index.concerns
      concern_paths = index.concerns.values.to_set

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb")
        next if ruby_non_production_path?(path)
        # Concern routes are drawn where they are `include`d; see below.
        next if concern_paths.includes?(path)
        content = ruby_source(path)
        next unless grape_api_file?(content, index.classes)
        mount_prefix = grape_file_mount_prefix(content, index)
        process_file(path, content, include_callee, mount_prefix)
      end

      # A concern no Grape file includes keeps the standalone read.
      concern_paths.each do |path|
        next if @used_concerns_mutex.synchronize { @used_concerns.includes?(path) }
        content = ruby_source(path)
        next unless grape_api_file?(content, index.classes)
        isolating_file_errors(path) { process_file(path, content, include_callee, grape_file_mount_prefix(content, index)) }
      end

      @result
    end

    # Cross-file Grape index: the set of classes that are (transitively) a
    # `Grape::API`, plus the prefix each class's routes inherit from the
    # aggregator(s) that `mount` it.
    record GrapeIndex,
      classes : Set(String),
      inherited : Hash(String, String),
      concerns : Hash(String, String)

    # `class <Child> < <Super>` declaration matcher (single capture: Super).
    GRAPE_CLASS_DEF = /^\s*class\s+[A-Z][\w:]*\s*<\s*([:\w][\w:]*)/
    # Full form capturing both Child and Super for the inheritance graph.
    GRAPE_CLASS_EDGE   = /^\s*class\s+([A-Z][\w:]*)\s*<\s*([:\w][\w:]*)/
    GRAPE_PREFIX_DECL  = /^\s*prefix\s+['":]([\w\/]+)['"]?/
    GRAPE_VERSION_DECL = /^\s*version\s+(.+)\busing:\s*:path\b/
    # `mount Child` / `mount Child => "/path"` (capture 2: the mount path).
    GRAPE_MOUNT_DECL = /^\s*mount\s+([:\w][\w:]*)(?:\s*=>\s*['"]([^'"]*)['"])?/

    # Build the transitive closure of Grape classes and the mount-inherited
    # prefix per class. Names are reduced to their final `::` segment so
    # `::API::Base`, `API::Base` and `Base` all match `class Base < Grape::API`.
    private def build_grape_index : GrapeIndex
      edges = {} of String => String                   # child class -> super class
      grape = Set(String).new                          # classes that ARE a Grape::API
      own_base = {} of String => String                # class -> its own prefix+version
      mounts = {} of String => Array({String, String}) # mounter class -> {mounted class, mount path}
      mounted = Set(String).new                        # classes mounted by someone
      concerns = {} of String => String                # concern module -> its file

      all_files.each do |path|
        next unless path.ends_with?(".rb")
        next if ruby_non_production_path?(path)
        content = ruby_source(path)
        # Only base-class definitions (`Grape::API`) and aggregators
        # (`mount`) feed the index; plain route files inherit from a custom
        # base and are recognised by `grape_api_file?` re-checking their
        # `< Base` against the resolved class set. Restricting the whole-tree
        # pre-pass to these two markers keeps it off the thousands of
        # unrelated `.rb` files in a large repo.
        next unless content.matches?(GRAPE_OR_MOUNT_MARKER_RE)
        if content.includes?("ActiveSupport::Concern") && content.includes?("included do")
          # ponytail: keyed by the module's last name segment, first file
          # wins; key by the full constant if same-named concerns collide.
          grape_concern_name(content).try { |name| concerns.put_if_absent(name) { path } }
        end
        next unless content.includes?("class ") && content.includes?("<")

        # Edges are collected for every `class X < Y`, but the
        # prefix/version/mount declarations are attributed to the file's
        # PRIMARY (first) Grape class. Aggregators routinely nest unrelated
        # helper classes (GitLab's `class MovedPermanentlyError <
        # StandardError` inside `class API`), and those nested defs must not
        # steal the `prefix :api` / `version 'v4'` / `mount` that belong to
        # the enclosing API class.
        primary : String? = nil
        prefix = ""
        version = ""
        content.each_line do |raw_line|
          # Cheap substring gates keep the per-line regex work off the
          # (vast) majority of lines in non-trivial repos — without them the
          # whole-tree pre-pass dominated Grape scan time on GitLab-scale
          # codebases.
          if raw_line.includes?("class ")
            next unless m = raw_line.match(GRAPE_CLASS_EDGE)
            child = grape_simple_class_name(m[1])
            super_full = m[2]
            if super_full.includes?("Grape::API")
              grape << child
            else
              edges[child] = grape_simple_class_name(super_full)
            end
            primary = child if primary.nil?
          elsif cls = primary
            if raw_line.includes?("prefix") && (m = raw_line.match(GRAPE_PREFIX_DECL))
              prefix = m[1]
              own_base[cls] = grape_join_segments(prefix, version)
            elsif raw_line.includes?("version") && (m = raw_line.match(GRAPE_VERSION_DECL))
              version = parse_first_grape_version(m[1])
              own_base[cls] = grape_join_segments(prefix, version)
            elsif raw_line.includes?("mount") && (m = raw_line.match(GRAPE_MOUNT_DECL))
              mounted_child = grape_simple_class_name(m[1])
              (mounts[cls] ||= [] of {String, String}) << {mounted_child, m[2]? || ""}
              mounted << mounted_child
              # A class reached only through `mount` (its own definition file
              # may not be in the pre-pass set) is still a Grape API — record
              # it so `grape_api_file?`/`grape_file_mount_prefix` recognise it.
              grape << mounted_child
            end
          end
        end
      end

      # Transitive Grape-ness through the inheritance chain.
      loop do
        changed = false
        edges.each do |child, parent|
          next if grape.includes?(child)
          if grape.includes?(parent)
            grape << child
            changed = true
          end
        end
        break unless changed
      end

      # Propagate prefixes down the mount graph from each root aggregator
      # (a Grape class nobody mounts). A child mounted by P inherits P's
      # prefix/version on top of P's own, and the `=> "/path"` mount paths
      # along the way. Grape puts every mount path ahead of the inherited
      # prefix (`Grape::Path#parts`: mount_path, root_prefix, version), so
      # the two are carried apart and joined in that order.
      inherited = Hash(String, String).new("")
      roots = grape.select { |c| !mounted.includes?(c) }
      visited = Set(String).new
      queue = roots.map { |r| {r, "", ""} }
      until queue.empty?
        cls, mount_path, prefix = queue.shift
        next unless visited.add?(cls)
        inherited[cls] = grape_join_segments(mount_path, prefix)
        child_prefix = grape_join_segments(prefix, own_base[cls]? || "")
        (mounts[cls]? || [] of {String, String}).each do |child, at|
          queue << {child, grape_join_segments(mount_path, at), child_prefix}
        end
      end

      GrapeIndex.new(grape, inherited, concerns)
    end

    # The module that `extend ActiveSupport::Concern`s: the last `module`
    # opened before that line.
    private def grape_concern_name(content : String) : String?
      name = nil
      content.each_line do |line|
        if m = line.match(GRAPE_MODULE_DEF)
          name = grape_simple_class_name(m[1])
        elsif line.matches?(GRAPE_CONCERN_EXT)
          return name
        end
      end
      nil
    end

    # `Grape::API` is absent from almost every `.rb` file in a large repo,
    # so `String#includes?` scanned each one end to end. One precompiled
    # matcher via `content_matches?` is the same test in a single pass.
    GRAPE_API_MARKER_RE = Regex.union("Grape::API")

    private def grape_api_file?(content : String, grape_classes : Set(String)) : Bool
      return true if content_matches?(content, GRAPE_API_MARKER_RE)
      # With no Grape classes anywhere in the project, the per-line membership
      # loop below can only ever miss, so skip it. This is the common case when
      # the whole-tree scan runs over a non-Grape repo (e.g. a Rails app, where
      # every controller is a `class X < ApplicationController`).
      return false if grape_classes.empty?
      return false unless content.includes?("class ") && content.includes?("<")
      content.each_line do |raw_line|
        next unless m = raw_line.match(GRAPE_CLASS_DEF)
        return true if grape_classes.includes?(grape_simple_class_name(m[1]))
      end
      false
    end

    private def grape_simple_class_name(name : String) : String
      name.lstrip(':').split("::").last
    end

    # The mount-inherited prefix for the Grape class(es) defined in this
    # file — i.e. the path under which an aggregator `mount`s them. Empty
    # when the file's class is a root aggregator or not mounted anywhere.
    private def grape_file_mount_prefix(content : String, index : GrapeIndex) : String
      content.each_line do |raw_line|
        next unless m = raw_line.match(GRAPE_CLASS_EDGE)
        cls = grape_simple_class_name(m[1])
        if index.classes.includes?(cls) && (prefix = index.inherited[cls]?) && !prefix.empty?
          return prefix
        end
      end
      ""
    end

    private def grape_join_segments(*segments : String) : String
      parts = [] of String
      segments.each do |seg|
        seg.split('/').each do |piece|
          trimmed = piece.strip
          parts << trimmed unless trimmed.empty?
        end
      end
      parts.join("/")
    end

    # A concern's routes are drawn under the includer's prefix, so an
    # `include` re-enters here with that context (`seen` stops cycles).
    private def process_file(path : String, content : String, include_callee : Bool, mount_prefix : String = "",
                             class_prefix : String = "", version_prefix : String = "",
                             outer_segments : Array(String) = [] of String, seen : Set(String) = Set(String).new) : Nil
      prefix_segments = outer_segments.dup
      block_kinds = [] of Symbol
      pending_params = [] of String
      params_block_depth = 0
      last_endpoint : Endpoint? = nil
      lines = content.lines
      # Statements as {text, source line index}; loop unrolling repeats lines.
      stmts = expand_grape_loops(lines.map_with_index { |text, i| {text, i} })
      skip_through = -1

      stmts.each_with_index do |(raw_line, index), pos|
        next if pos <= skip_through
        line = Noir::RubyCalleeExtractor.strip_comment(raw_line, preserve_strings: true)
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        if params_block_depth > 0
          # Grape allows nested validation blocks (`requires :x, type: Hash do
          # ... end`), so the params block closes only when depth returns to 0.
          # A plain boolean let the first inner `end` close it early, leaking the
          # remaining `end`(s) to the main parser, which then popped the
          # enclosing namespace/resource prefix frame.
          if grape_end?(stripped)
            params_block_depth -= 1
            next if params_block_depth <= 0
          else
            params_block_depth += ruby_do_block_open_delta(stripped)
            stripped.scan(/(?:requires|optional)\s+[:\'"]([\w]+)[\'"]?/) do |m|
              pending_params << m[1] if m.size > 1
            end
          end
          next
        end

        # Join a statement whose options continue on the following lines;
        # its `do` (where callees start) is on the last of them.
        do_index = index
        if stripped.ends_with?(',') && stripped.matches?(GRAPE_CONTINUED_DSL)
          last = pos
          while stripped.ends_with?(',') && last + 1 < stmts.size && last - pos < MAX_CONTINUATION
            last += 1
            stripped = "#{stripped} #{Noir::RubyCalleeExtractor.strip_comment(stmts[last][0], preserve_strings: true).strip}"
          end
          skip_through = last
          do_index = stmts[last][1]
        end

        if stripped == "params do" || stripped.starts_with?("params do")
          params_block_depth = 1
          next
        end

        if m = stripped.match(/^(?:prefix|route_prefix)\s+['":]([\w\/]+)['"]?/)
          class_prefix = m[1].to_s
          next
        end

        if m = stripped.match(/^version\s+(.+)\busing:\s*:path\b/)
          version_prefix = parse_first_grape_version(m[1])
          next
        end

        if m = stripped.match(GRAPE_PREFIX_LITERAL)
          prefix_segments << m[1].to_s
          block_kinds << :prefix
          next
        end

        if m = stripped.match(GRAPE_PREFIX_EXPR)
          prefix_segments << "{#{m[1]}}"
          block_kinds << :prefix
          next
        end

        if (m = stripped.match(GRAPE_INCLUDE)) && (concern = @grape_concerns[grape_simple_class_name(m[1])]?) &&
           concern != path && !seen.includes?(concern) && seen.size < 4
          @used_concerns_mutex.synchronize { @used_concerns << concern }
          process_file(concern, ruby_source(concern), include_callee, mount_prefix, class_prefix, version_prefix, prefix_segments, seen | Set{path})
          next
        end

        if m = stripped.match(/^route_param\s+(?::(\w+)|['"]([^'"]+)['"])(?:\s*,[^#]*?)?\s*do\b/)
          name = (m[1]? || m[2]?).to_s
          unless name.empty?
            prefix_segments << "{#{name}}"
            block_kinds << :prefix
            next
          end
        end

        verb_handled = false
        GRAPE_VERBS.each do |verb|
          # Cheap prefix gate before the (precompiled) anchored regexes:
          # skips the regex work entirely for the vast majority of lines
          # that don't open with a verb keyword.
          next unless stripped.starts_with?(verb)
          next if stripped.size > verb.size && (stripped[verb.size].alphanumeric? || stripped[verb.size] == '_')

          if m = stripped.match(GRAPE_VERB_WITH_PATH[verb])
            raw_match = (m[1]? || "").to_s
            raw_path = grape_literal_or_param_path(raw_match)
            ep_path = build_path(mount_prefix, class_prefix, version_prefix, prefix_segments, raw_path)
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = Endpoint.new(ep_path, verb.upcase, details)

            extract_path_params(ep_path).each do |param_name|
              endpoint.push_param(Param.new(param_name, "", "path"))
            end

            pending_params.each do |param_name|
              next if raw_path.includes?(":#{param_name}")
              endpoint.push_param(Param.new(param_name, "", declared_param_type(verb)))
            end
            pending_params.clear

            attach_do_block_callees(endpoint, lines, do_index, path) if include_callee
            @result << endpoint
            last_endpoint = endpoint
            block_kinds << :other unless stripped.match(/\bend\b/)
            verb_handled = true
            break
          end

          if m = stripped.match(GRAPE_VERB_BARE_DO[verb])
            ep_path = build_path(mount_prefix, class_prefix, version_prefix, prefix_segments, "")
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = Endpoint.new(ep_path, verb.upcase, details)

            extract_path_params(ep_path).each do |param_name|
              endpoint.push_param(Param.new(param_name, "", "path"))
            end

            pending_params.each do |param_name|
              endpoint.push_param(Param.new(param_name, "", declared_param_type(verb)))
            end
            pending_params.clear

            attach_do_block_callees(endpoint, lines, do_index, path) if include_callee
            @result << endpoint
            last_endpoint = endpoint
            block_kinds << :other unless stripped.match(/\bend\b/)
            verb_handled = true
            break
          end
        end

        next if verb_handled

        if le = last_endpoint
          # Require a symbol (`:name`) or string (`'name'`/`"name"`) key.
          # The old `['"]?:?` made both optional, so a bare-variable
          # subscript like `headers[key]` (where `key` is a local) was
          # mis-captured as a literal header named `key`.
          line.scan(/\bparams\[\s*(?::([\w-]+)|['"]([\w-]+)['"])\s*\]/) do |match|
            name = (match[1]? || match[2]?).to_s
            push_grape_param(le, Param.new(name, "", "query")) unless name.empty?
          end
          line.scan(/\bheaders\[\s*(?::([\w-]+)|['"]([\w-]+)['"])\s*\]/) do |match|
            name = (match[1]? || match[2]?).to_s
            push_grape_param(le, Param.new(name, "", "header")) unless name.empty?
          end
          line.scan(/\bcookies\[\s*(?::([\w-]+)|['"]([\w-]+)['"])\s*\]/) do |match|
            name = (match[1]? || match[2]?).to_s
            push_grape_param(le, Param.new(name, "", "cookie")) unless name.empty?
          end
        end

        if ruby_do_block_open_delta(stripped) > 0
          block_kinds << :other
        end

        if grape_end?(stripped)
          popped = block_kinds.pop?
          if popped == :prefix && !prefix_segments.empty?
            prefix_segments.pop
          end
        end
      end
    end

    # Grape accepts the route path as a bare Ruby symbol (`get :status`,
    # `delete :test`) or a string (`get '/users/:id'`). A symbol is
    # stringified to a LITERAL segment — `/status`, `/test` — while a
    # `:name` token inside a string is a dynamic param. Quote-stripping
    # alone erased that distinction, so the common `delete :test` idiom
    # surfaced as the bogus param route `/{test}` instead of `/test`.
    # Drop the leading colon of the symbol form so `build_path` keeps it
    # literal; leave the string form (and any in-path `:params`) intact.
    private def grape_literal_or_param_path(raw_match : String) : String
      literal_symbol = raw_match.starts_with?(':')
      path = raw_match.gsub(/['"]/, "")
      literal_symbol ? path.lchop(':') : path
    end

    # `params do; requires :x; end` declares the request's params; Grape reads
    # them from the query string on a bodyless verb and the body otherwise.
    private def declared_param_type(verb : String) : String
      verb.in?("get", "head", "delete") ? "query" : "json"
    end

    private def push_grape_param(endpoint : Endpoint, param : Param)
      return if param.param_type == "query" && endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == "path" }
      # A `params do; requires :x; end` block already declared `:x` as a json
      # body param; a later `params[:x]` read in the handler body must not
      # re-add it as a separate `query` param. The declared type wins.
      return if param.param_type == "query" && endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == "json" }
      endpoint.push_param(param)
    end

    private def parse_first_grape_version(args : String) : String
      if m = args.match(/['"]([^'"]+)['"]/)
        return m[1]
      end
      if m = args.match(/:(\w+)/)
        return m[1]
      end
      ""
    end

    private def build_path(mount_prefix : String, class_prefix : String, version_prefix : String, prefix_segments : Array(String), raw : String) : String
      parts = [] of String
      parts << mount_prefix unless mount_prefix.empty?
      parts << class_prefix unless class_prefix.empty?
      parts << version_prefix unless version_prefix.empty?
      prefix_segments.each { |s| parts << s }
      unless raw.empty?
        cleaned = raw.starts_with?('/') ? raw[1..] : raw
        parts << cleaned unless cleaned.empty?
      end
      joined = parts.reject(&.empty?).join("/")
      path = joined.empty? ? "/" : "/#{joined}"
      # A `#{var}` no static loop resolved never matches a request as
      # written; it is a runtime segment, like `:var`.
      path.gsub(/#\{\s*([a-zA-Z_]\w*)[^}]*\}/) { "{#{$~[1]}}" }.gsub(/:([a-zA-Z_][\w]*)/) { "{#{$~[1]}}" }
    end

    private def grape_end?(stripped : String) : Bool
      stripped == "end" || stripped.starts_with?("end ") || stripped.starts_with?("end#")
    end

    # Unrolls `.each do |var|` over a literal list into one copy of its body
    # per value, substituting `#{var}` and a bare `resource var` (Rails'
    # `expand_static_loops` does the same for routes.rb). Copies keep the
    # source line they came from.
    private def expand_grape_loops(stmts : Array({String, Int32}), depth : Int32 = 0) : Array({String, Int32})
      return stmts if depth > MAX_LOOP_DEPTH
      return stmts unless stmts.any? { |(text, _)| text.includes?(".each") && text.matches?(GRAPE_LOOP_OPENER) }

      result = [] of {String, Int32}
      pos = 0
      while pos < stmts.size
        text = stmts[pos][0]
        m = text.includes?(".each") ? text.match(GRAPE_LOOP_OPENER) : nil
        values = m.try { |md| grape_loop_values(md[1]) }
        if m.nil? || values.nil? || values.size > MAX_LOOP_VALUES || result.size > MAX_LOOP_OUTPUT
          result << stmts[pos]
          pos += 1
          next
        end

        open = 1
        cursor = pos + 1
        body = [] of {String, Int32}
        while cursor < stmts.size
          inner = Noir::RubyCalleeExtractor.strip_comment(stmts[cursor][0]).strip
          if grape_end?(inner)
            open -= 1
            break if open == 0
          else
            open += ruby_do_block_open_delta(inner)
          end
          body << stmts[cursor]
          cursor += 1
        end

        expanded = expand_grape_loops(body, depth + 1)
        var = Regex.escape(m[2])
        interpolated = Regex.new("\\#\\{\\s*#{var}(?:\\.(pluralize|to_s|to_sym))?\\s*\\}")
        bare = Regex.new("^(\\s*(?:resource|resources|namespace|group|segment)\\s+)#{var}(?:\\.(pluralize|to_s|to_sym))?\\b")
        values.each do |value|
          break if result.size > MAX_LOOP_OUTPUT
          plural = Noir::RubyInflector.pluralize(value)
          expanded.each do |(line, origin)|
            line = line.gsub(interpolated) { |_, md| md[1]? == "pluralize" ? plural : value }
            line = line.sub(bare) { |_, md| "#{md[1]}'#{md[2]? == "pluralize" ? plural : value}'" }
            result << {line, origin}
          end
        end
        pos = cursor + 1 # past the loop's `end`
      end
      result
    end

    # The literal values a loop receiver yields to its first block variable:
    # `%w[a b]`/`%i[a b]` words, a `[:a, "b"]` array of literals, or a hash
    # literal's keys. Nil when any element is not a literal.
    private def grape_loop_values(receiver : String) : Array(String)?
      return receiver[3...-1].split(/\s+/).reject(&.empty?) if receiver.starts_with?('%')
      if receiver.starts_with?('{')
        keys = receiver.scan(/(?:\{|,)\s*(?:['"]([\w-]+)['"]\s*=>|:(\w+)\s*=>|(\w+):\s)/).map { |k| (k[1]? || k[2]? || k[3]?).to_s }
        return keys.empty? ? nil : keys
      end
      values = [] of String
      receiver[1...-1].split(',').each do |item|
        item = item.strip
        next if item.empty?
        md = item.match(/\A(?::(\w+)|'([\w\/-]*)'|"([\w\/-]*)")\z/)
        return unless md
        values << (md[1]? || md[2]? || md[3]?).to_s
      end
      values.empty? ? nil : values
    end

    private def extract_path_params(raw : String) : Array(String)
      names = [] of String
      raw.scan(/:([a-zA-Z_][\w]*)/) do |m|
        names << m[1] if m.size > 1
      end
      raw.scan(/\{([a-zA-Z_][\w]*)\}/) do |m|
        names << m[1] if m.size > 1 && !names.includes?(m[1])
      end
      names
    end
  end
end
