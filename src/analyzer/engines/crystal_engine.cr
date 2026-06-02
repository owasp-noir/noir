require "../../models/analyzer"
require "../../miniparsers/crystal_callee_extractor"

module Analyzer::Crystal
  abstract class CrystalEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # `.cr` extension filter plus `lib/` exclusion baked in (shards puts
    # dependencies under `lib/` and we don't want to analyze them).
    # Subclasses that need a custom scan shape can override `analyze`
    # (e.g. Amber/Kemal run a public-dir post-pass after the file walk).
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".cr"
          next if crystal_dependency_path?(path)
          # Crystal's standard test directory is `spec/`, and test
          # files always end in `_spec.cr`. Crystal framework repos
          # (lucky, marten, amber, kemal) park hundreds of route
          # declarations there to exercise the framework. Production
          # code never adopts either convention. The `spec/` dir
          # is checked relative to the project root so nested
          # fixtures under noir's own `spec/functional_test/...`
          # tree don't accidentally trip the filter.
          next if crystal_spec_path?(path)

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end

    # `*_spec.cr` is Crystal's official spec filename — unambiguous
    # at any depth. The `spec/` directory is only treated as test
    # when it sits at the project root (or the immediate child of
    # one of the configured `base_paths`); inside our fixture tree
    # the framework apps themselves live under a `spec/` ancestor.
    private def crystal_spec_path?(path : String) : Bool
      return true if File.basename(path).ends_with?("_spec.cr")
      base_paths.any? do |root|
        normalized = root.ends_with?("/") ? root : "#{root}/"
        path.starts_with?("#{normalized}spec/")
      end
    end

    # Shards installs dependencies under a `lib/` directory; skip them.
    # Match the `lib/` path SEGMENT, not the bare substring "lib", so
    # application directories like `library/`, `glib/`, or a project
    # literally named `amber-library` aren't silently dropped (that bug
    # made a real Amber app surface 0 routes — only public files).
    protected def crystal_dependency_path?(path : String) : Bool
      path.includes?("/lib/") || path.starts_with?("lib/")
    end

    # Crystal `"…"` strings interpolate `#{expr}`. The Kemal/Lucky/
    # Amber/Marten/Grip route extractors capture the literal
    # characters between quotes, so `get "/api/#{VERSION}/items"`
    # came out as `/api/#{VERSION}/items` with the `#{VERSION}`
    # leaking into the URL. Rewrite it as `{name}` so the path-
    # parameter extractor picks it up and the URL template reads
    # cleanly. Mirrors the Python f-string, Ruby `#{}`, and PHP
    # `$var` fixes earlier this pass.
    protected def normalize_crystal_interpolation(path : String) : String
      path.gsub(/\#\{([^}]+)\}/) { |_| "{#{$~[1].strip}}" }
    end

    # A genuine Kemal/Lucky/Amber route path always begins with `/`
    # (root, nested, or a glob like `/*`), a normalized interpolation
    # `{…}` (see `normalize_crystal_interpolation`), or a bare glob `*`.
    #
    # The verb regexes (`get "…"`, `post "…"`, …) are deliberately loose
    # so they catch every routing style, but that also lets them fire on
    # the verb appearing inside a string or sentence rather than as a
    # routing call — `method: "get", template: "…"`, `nested_arrays("post")`,
    # the macro literal `{"get", "post"}`, or the word "post" in prose.
    # Those produce captures that start with `,`, `)`, `>`, whitespace, or
    # a letter, surfacing as junk endpoints like `/, template:` or `/)[`.
    # Real apps (invidious, lucky's guide site) hit this constantly, so
    # reject anything whose first character isn't a path lead-in.
    protected def valid_crystal_route_path?(path : String) : Bool
      return false if path.empty?
      first = path[0]
      first == '/' || first == '*' || first == '{'
    end

    protected def attach_crystal_callees(endpoint : Endpoint, callees : Array(Noir::CrystalCalleeExtractor::Entry))
      Noir::CrystalCalleeExtractor.attach_to(endpoint, callees)
    end

    # method name => list of `{full_namespace, callees}` definitions.
    alias ActionIndex = Hash(String, Array(Tuple(String, Array(Noir::CrystalCalleeExtractor::Entry))))

    # Cross-file controller/action index for the `verb "/path", Controller,
    # :action` routing style — invidious registers every Kemal route as
    # `get "/", Routes::Misc, :home` with the handler `def self.home(env)`
    # living in another file, and Amber's route table works the same way.
    # Without this, those apps surface routes with zero callees (no inline
    # `do` block to read). Built once per project and only when callee/
    # ai-context extraction is requested, so default scans pay nothing.
    protected def build_crystal_action_index(paths : Array(String)) : ActionIndex
      index = ActionIndex.new
      paths.each do |path|
        next if File.directory?(path)
        next unless File.exists?(path) && File.extname(path) == ".cr"
        next if crystal_dependency_path?(path)
        begin
          collect_actions_into(index, File.read_lines(path), path)
        rescue e
          logger.debug "crystal action index #{path}: #{e}"
        end
      end
      index
    end

    # Resolve the callees of `Controller#action` against the index. The
    # route names the controller relatively (`Routes::Misc`), the index
    # keys it fully (`Invidious::Routes::Misc`), so match by suffix.
    protected def resolve_action_callees(index : ActionIndex,
                                         controller : String,
                                         action : String) : Array(Noir::CrystalCalleeExtractor::Entry)?
      if entries = index[action]?
        if match = entries.find { |ns, _| ns == controller || ns.ends_with?("::#{controller}") }
          return match[1]
        end
      end
      nil
    end

    # Track the enclosing module/class by indentation rather than by
    # counting `do`/`end`. Method bodies in real controllers are full of
    # heredocs, `{% … %}` macros, and `XML.build do … end` blocks that
    # throw off keyword-based depth counting and prematurely "close" the
    # module, dropping every method defined after them. Indentation is the
    # one signal those constructs can't corrupt: a namespace stays open
    # until a line dedents to or past the column where it was declared.
    protected def collect_actions_into(index : ActionIndex, lines : Array(String), path : String) : Nil
      namespace_stack = [] of NamedTuple(name: String, indent: Int32)

      lines.each_with_index do |raw, i|
        line = Noir::CrystalCalleeExtractor.strip_comment(raw)
        content = line.lstrip
        next if content.empty?
        indent = line.size - content.size

        # Anything at this column or shallower has closed the namespaces
        # opened deeper than it.
        while !namespace_stack.empty? && namespace_stack.last[:indent] >= indent
          namespace_stack.pop
        end

        if ns = content.match(/^(?:abstract\s+)?(?:module|class|struct)\s+([A-Z]\w*(?:::[A-Z]\w*)*)/)
          namespace_stack << {name: ns[1], indent: indent}
          next
        end

        if def_match = content.match(/^(?:(?:private|protected)\s+)?def\s+(?:self\.)?([A-Za-z_]\w*[!?=]?)/)
          next if namespace_stack.empty?
          if method_body = extract_crystal_def_block(lines, i)
            body, body_start_line = method_body
            callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
            full_ns = namespace_stack.map(&.[:name]).join("::")
            (index[def_match[1]] ||= Array(Tuple(String, Array(Noir::CrystalCalleeExtractor::Entry))).new) << {full_ns, callees}
          end
        end
      end
    end

    protected def extract_crystal_do_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      start_line = Noir::CrystalCalleeExtractor.strip_comment(lines[start_index]).strip
      match = start_line.match(/\bdo\b(?:\s*\|[^|]*\|)?(.*)$/)
      return unless match

      body_lines = [] of String
      body_start_line = start_index + 2
      depth = 1
      tail = match[1].strip
      tail = tail[1, tail.size - 1].strip if tail.starts_with?(";")

      unless tail.empty?
        body_start_line = start_index + 1
        if m = tail.match(/^(.*?)(?:;\s*)?end\b/)
          return {m[1].strip, body_start_line}
        end

        body_lines << tail
        depth += crystal_do_block_open_delta(tail)
      end

      index = start_index + 1
      while index < lines.size
        raw_body_line = lines[index]
        body_line = Noir::CrystalCalleeExtractor.strip_comment(raw_body_line).strip

        if crystal_closes_block?(body_line)
          depth -= 1
          break if depth == 0
          body_lines << raw_body_line
          index += 1
          next
        end

        body_lines << raw_body_line
        depth += crystal_do_block_open_delta(body_line)
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    protected def extract_crystal_def_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      def_line = Noir::CrystalCalleeExtractor.strip_comment(lines[start_index]).strip
      if semicolon_index = def_line.index(';')
        tail = def_line[(semicolon_index + 1)..].strip
        if m = tail.match(/^(.*?)(?:;\s*)?end\b/)
          return {m[1].strip, start_index + 1}
        end
      end

      body_lines = [] of String
      body_start_line = start_index + 2
      depth = 1
      index = start_index + 1

      while index < lines.size
        raw_body_line = lines[index]
        body_line = Noir::CrystalCalleeExtractor.strip_comment(raw_body_line).strip

        if crystal_closes_block?(body_line)
          depth -= 1
          break if depth == 0
          body_lines << raw_body_line
          index += 1
          next
        end

        body_lines << raw_body_line
        depth += crystal_do_block_open_delta(body_line)
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    protected def crystal_do_block_open_delta(line : String) : Int32
      return 0 if line.empty?
      return 1 if line.match(/\bdo\b/) && !line.match(/\bend\b/)
      return 1 if line.match(/(?:^|=[^=>])\s*(if|unless|case|begin|while|until|for|class|module|def|macro)\b/) && !line.match(/\bend\b/)
      0
    end

    private def crystal_closes_block?(line : String) : Bool
      !!line.match(/^end\b/)
    end
  end
end
