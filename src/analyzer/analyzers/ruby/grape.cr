require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Grape < RubyEngine
    GRAPE_VERBS = ["get", "post", "put", "delete", "patch", "head", "options"]

    # Crystal recompiles an interpolated regex literal (`/^#{verb}.../`)
    # on every evaluation — ~11000x slower than a precompiled one — so
    # matching the verb DSL inside the per-line loop used to recompile
    # 14 regexes for every line of every Grape file. Build the per-verb
    # patterns once at load time instead. `_WITH_PATH` matches
    # `get '/users' do` (capturing the path literal/symbol); `_BARE_DO`
    # matches the path-less `get do` form.
    GRAPE_VERB_WITH_PATH = GRAPE_VERBS.to_h do |verb|
      {verb, /^#{verb}\b(?:\s+(['":][\w\/\-:]+[\'""]?))?(?:\s*,[^#]*?)?\s*do\b/}
    end
    GRAPE_VERB_BARE_DO = GRAPE_VERBS.to_h do |verb|
      {verb, /^#{verb}\s+do\b/}
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

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

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb")
        next if ruby_non_production_path?(path)
        content = read_file_content(path)
        next unless grape_api_file?(content, index.classes)
        mount_prefix = grape_file_mount_prefix(content, index)
        process_file(path, content, include_callee, mount_prefix)
      end

      @result
    end

    # Cross-file Grape index: the set of classes that are (transitively) a
    # `Grape::API`, plus the prefix each class's routes inherit from the
    # aggregator(s) that `mount` it.
    record GrapeIndex,
      classes : Set(String),
      inherited : Hash(String, String)

    # `class <Child> < <Super>` declaration matcher (single capture: Super).
    GRAPE_CLASS_DEF = /^\s*class\s+[A-Z][\w:]*\s*<\s*([:\w][\w:]*)/
    # Full form capturing both Child and Super for the inheritance graph.
    GRAPE_CLASS_EDGE   = /^\s*class\s+([A-Z][\w:]*)\s*<\s*([:\w][\w:]*)/
    GRAPE_PREFIX_DECL  = /^\s*prefix\s+['":]([\w\/]+)['"]?/
    GRAPE_VERSION_DECL = /^\s*version\s+(.+)\busing:\s*:path\b/
    GRAPE_MOUNT_DECL   = /^\s*mount\s+([:\w][\w:]*)/

    # Build the transitive closure of Grape classes and the mount-inherited
    # prefix per class. Names are reduced to their final `::` segment so
    # `::API::Base`, `API::Base` and `Base` all match `class Base < Grape::API`.
    private def build_grape_index : GrapeIndex
      edges = {} of String => String         # child class -> super class
      grape = Set(String).new                # classes that ARE a Grape::API
      own_base = {} of String => String      # class -> its own prefix+version
      mounts = {} of String => Array(String) # mounter class -> mounted classes
      mounted = Set(String).new              # classes mounted by someone

      all_files.each do |path|
        next unless path.ends_with?(".rb")
        next if ruby_non_production_path?(path)
        next if File.directory?(path)
        content = read_file_content(path)
        # Only base-class definitions (`Grape::API`) and aggregators
        # (`mount`) feed the index; plain route files inherit from a custom
        # base and are recognised by `grape_api_file?` re-checking their
        # `< Base` against the resolved class set. Restricting the whole-tree
        # pre-pass to these two markers keeps it off the thousands of
        # unrelated `.rb` files in a large repo.
        next unless content.includes?("Grape") || content.includes?("mount ")
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
              (mounts[cls] ||= [] of String) << mounted_child
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
      # full path = P's inherited prefix + P's own prefix/version.
      inherited = Hash(String, String).new("")
      roots = grape.select { |c| !mounted.includes?(c) }
      visited = Set(String).new
      queue = roots.map { |r| {r, ""} }
      until queue.empty?
        cls, prefix = queue.shift
        next if visited.includes?(cls)
        visited << cls
        inherited[cls] = prefix
        child_prefix = grape_join_segments(prefix, own_base[cls]? || "")
        (mounts[cls]? || [] of String).each do |child|
          queue << {child, child_prefix}
        end
      end

      GrapeIndex.new(grape, inherited)
    end

    private def grape_api_file?(content : String, grape_classes : Set(String)) : Bool
      return true if content.includes?("Grape::API")
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

    private def process_file(path : String, content : String, include_callee : Bool, mount_prefix : String = "") : Nil
      prefix_segments = [] of String
      block_kinds = [] of Symbol
      class_prefix = ""
      version_prefix = ""
      pending_params = [] of String
      params_block_depth = 0
      last_endpoint : Endpoint? = nil
      lines = content.lines

      lines.each_with_index do |raw_line, index|
        line = Noir::RubyCalleeExtractor.strip_comment(raw_line, preserve_strings: true)
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        if params_block_depth > 0
          # Grape allows nested validation blocks (`requires :x, type: Hash do
          # ... end`), so the params block closes only when depth returns to 0.
          # A plain boolean let the first inner `end` close it early, leaking the
          # remaining `end`(s) to the main parser, which then popped the
          # enclosing namespace/resource prefix frame.
          if stripped == "end" || stripped.starts_with?("end ") || stripped.starts_with?("end#")
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

        if m = stripped.match(/^(?:resource|resources|namespace|group|segment)\s+['":]([\w\/\-:]+)[\'""]?(?:\s*,[^#]*?)?\s*do\b/)
          prefix_segments << m[1].to_s
          block_kinds << :prefix
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
              endpoint.push_param(Param.new(param_name, "", "json"))
            end
            pending_params.clear

            attach_route_callees(endpoint, lines, index, path) if include_callee
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
              endpoint.push_param(Param.new(param_name, "", "json"))
            end
            pending_params.clear

            attach_route_callees(endpoint, lines, index, path) if include_callee
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

        if stripped == "end" || stripped.starts_with?("end ") || stripped.starts_with?("end#")
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

    private def push_grape_param(endpoint : Endpoint, param : Param)
      return if param.param_type == "query" && endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == "path" }
      # A `params do; requires :x; end` block already declared `:x` as a json
      # body param; a later `params[:x]` read in the handler body must not
      # re-add it as a separate `query` param. The declared type wins.
      return if param.param_type == "query" && endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == "json" }
      return if endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
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

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      if block = extract_ruby_do_block(lines, index)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
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
      path.gsub(/:([a-zA-Z_][\w]*)/) { "{#{$~[1]}}" }
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
