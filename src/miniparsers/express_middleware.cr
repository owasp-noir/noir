require "../models/endpoint"
require "../analyzer/analyzers/javascript/express_constants"
require "./js_mount_prefix"
require "../tagger/framework_taggers/prefix_scope"

module Noir
  # A scan-local companion to the prefix table. Each placed prefix carries the
  # parent router registrations traversed to reach it, including the point at
  # which Express enters the child. Later .use calls on the parent cannot run.
  class ExpressMiddleware
    alias Keys = Analyzer::Javascript::ExpressConstants
    record Use, file : String, receiver : String, offset : Int32, prefix : String?,
      args : Array(String), verb : String = "use", written : String? = nil do
      # Only arguments before the selected router can run inside its routes.
      # A wrapper around the router is itself a middleware at the mount.
      def before_child(name : String?, inline_require : String? = nil) : Array(String)
        return [] of String unless name
        before = [] of String
        flattened(args).each do |arg|
          break if arg.strip == name || arg.strip.starts_with?("#{name}(") ||
                   (inline_require && arg.includes?(inline_require))
          before << arg
          break if JSLiteralScanner.blank_literals(arg).matches?(/(?<![\w$])#{Regex.escape(name)}(?![\w$])/)
        end
        before
      end

      private def flattened(args : Array(String)) : Array(String)
        args.flat_map do |arg|
          source = arg.strip
          if source.starts_with?('[') && source.ends_with?(']')
            flattened(TopLevelSplit.split(source[1...-1], ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS))
          else
            [arg]
          end
        end
      end
    end

    # The old unresolved-prefix heuristic only recognized literal scopes.
    # Keep the spelling separately from the analyzer's resolved prefix.
    def self.literal_scope(expression : String, resolved : String) : String?
      first = expression.strip
      if match = first.match(/\A['"`]([^'"`]*)['"`]/)
        return match[1]
      end
      resolved if first.starts_with?('[') && first.scan(/['"`]([^'"`]*)['"`]/).any? { |item| item[1] == resolved }
    end

    record Frame, registration : Use, parent_prefix : String, before_child : Array(String)

    @uses = {} of Tuple(String, String) => Array(Use)
    @frames = {} of Tuple(String, String) => Array(Frame)

    @fallback_scopes : Array(Tuple(String, Use))?
    @bindings = {} of Tuple(String, String) => Array(Range(Int32, Int32))
    @line_starts = {} of String => Array(Int32)

    def register(site : Use)
      list = (@uses[{site.file, site.receiver}] ||= [] of Use)
      list << site unless list.includes?(site)
    end

    def finish
      @uses.each_value(&.sort_by!(&.offset))
    end

    # A receiver belongs to its nearest declaration. Two router factories
    # can each declare a variable called router in the same module.
    def index_bindings(file : String, content : String)
      file = PathScope.expand(file)
      return unless @uses.any? { |(path, _), _| path == file }
      TreeSitter.parse_js_family(content, file) do |root|
        TreeSitter.walk(root) do |node|
          type = TreeSitter.node_type(node)
          if type == "variable_declarator"
            name = TreeSitter.field(node, "name") || next
            next unless TreeSitter.node_type(name) == "identifier"
            scope = TreeSitter.parent(node)
            until scope.nil? || TreeSitter.node_type(scope).in?("statement_block", "program")
              scope = TreeSitter.parent(scope)
            end
            add_binding(file, TreeSitter.node_text(name, content), scope) if scope
          elsif type == "formal_parameters"
            scope = TreeSitter.parent(node) || next
            TreeSitter.each_named_child(node) do |param|
              name = TreeSitter.field(param, "pattern") || param
              add_binding(file, TreeSitter.node_text(name, content), scope) if TreeSitter.node_type(name) == "identifier"
            end
          end
        end
      end
    end

    private def add_binding(file, name, scope)
      key = {file, name}
      return unless @uses.has_key?(key)
      (@bindings[key] ||= [] of Range(Int32, Int32)) << (LibTreeSitter.ts_node_start_byte(scope).to_i...LibTreeSitter.ts_node_end_byte(scope).to_i)
    end

    private def binding_at(key, at)
      @bindings[key]?.try(&.select(&.includes?(at)).min_by? { |range| range.end - range.begin })
    end

    private def fallback_scopes
      @fallback_scopes ||= build_fallback_scopes
    end

    private def build_fallback_scopes
      scopes = [] of Tuple(String, Use)
      # If only a suffix of the URL was recovered, preserve the earlier
      # literal-prefix guess. Derive its bases from the placements on hand.
      @uses.each do |(file, receiver), sites|
        next unless sites.any?(&.written)
        next unless File.extname(file).in?(".js", ".ts", ".mjs", ".cjs")
        file_bases = CodeLocator.instance.all(Keys.file_key(file))
        content = CodeLocator.instance.read_source(file) || next
        bases = fallback_bases(file, receiver, content, file_bases)
        sites.each do |site|
          written = site.written || next
          written = written.sub(/\/(?:\(\.\*\)|\*(?:\/.*)?)?\z/, "")
          (bases.empty? ? [""] : bases.uniq).each do |base|
            scopes << {URLPath.join(base, written), site}
          end
        end
      end
      scopes
    end

    # The unresolved-prefix heuristic treated a declared Express app as a
    # root, and only followed literal same-file router bindings. Project
    # those portions of the scanner's existing frames onto the visible URL.
    private def fallback_bases(file, receiver, content, file_bases)
      return [""] if app_binding?(content, receiver)
      bases = [] of String
      binding = Keys.binding_key(file, receiver).name
      @frames.each do |(key, _), frames|
        next unless key == binding
        child = receiver
        segments = [] of String
        frames.reverse_each do |frame|
          site = frame.registration
          break unless site.file == file && site.args.any? { |arg| arg.strip == child }
          break unless content.matches?(/\b(?:const|let|var)\s+#{Regex.escape(child)}\s*=\s*(?:express\s*\.\s*Router|Router)\s*\(/)
          segments.unshift(site.written || "")
          child = site.receiver
        end
        next if segments.empty?
        outers = app_binding?(content, child) || file_bases.empty? ? [""] : file_bases
        outers.each { |base| bases << segments.reduce(base) { |parent, path| URLPath.join(parent, path) } }
      end
      bases.empty? ? file_bases : bases.uniq!
    end

    private def app_binding?(content, name)
      content.matches?(/\b(?:const|let|var)\s+#{Regex.escape(name)}\s*=\s*(?:express|require\s*\(\s*['"]express['"]\s*\))\s*\(\s*\)/)
    end

    def place(keys : Array(String), prefix : String, parent_key : String?, frame : Frame)
      parent = @frames[{parent_key, frame.parent_prefix.rstrip('/')}]? if parent_key
      chain = (parent || [] of Frame) + [frame]
      keys.each { |key| @frames[{key, prefix.rstrip('/')}] ||= chain }
    end

    def carry(from : String, to : String, prefix : String)
      chain = @frames[{from, prefix.rstrip('/')}]?
      @frames[{to, prefix.rstrip('/')}] ||= chain if chain
    end

    private def ancestry(keys : Array(String), prefix : String) : Array(Frame)
      keys.each do |key|
        if frames = @frames[{key, prefix.rstrip('/')}]?
          return frames
        end
      end
      [] of Frame
    end

    def chain(file : String, receiver : String, offset : Int32, prefix : String, outer : String,
              keys : Array(String), url : String, args : Array(String), *, forwarded_steps : Array(RouteMiddleware)? = nil, local_frames : Array(Frame)? = nil) : Array(RouteMiddleware)
      file = PathScope.expand(file)
      steps = [] of RouteMiddleware
      unread = url.includes?(JSMountPrefix::UNREAD)
      if unread
        append_fallback(steps, file, receiver, offset, url, !forwarded_steps.nil?)
      else
        if local_frames
          frames = ancestry(keys, outer) + local_frames.map { |frame| frame.copy_with(parent_prefix: URLPath.join(outer, frame.parent_prefix)) }
        else
          frames = ancestry([Keys.binding_key(file, receiver).name], prefix)
          frames = ancestry(keys, outer) if frames.empty?
        end
        frames.each do |frame|
          site = frame.registration
          append_scoped(steps, site.file, site.receiver, site.offset, frame.parent_prefix, url)
          frame.before_child.each do |arg|
            steps << RouteMiddleware.new(arg, site.file, :mount, false, site.receiver, site.prefix, site.verb)
          end
        end
        append_scoped(steps, file, receiver, offset, prefix, url)
      end
      return steps.concat(forwarded_steps) if forwarded_steps
      args.each_with_index do |arg, i|
        steps << RouteMiddleware.new(arg, file, :route, i == args.size - 1)
      end
      steps
    end

    private def append_fallback(steps, file, receiver, offset, url, helper)
      if !helper && File.extname(file).in?(".js", ".ts", ".mjs", ".cjs")
        @uses[{file, receiver}]?.try &.each do |site|
          next if site.offset >= offset || site.written || site.verb != "use"
          # The previous receiver heuristic only attributed preceding lines.
          starts = @line_starts[file] ||= begin
            bytes = (CodeLocator.instance.read_source(file) || "").to_slice
            (0...bytes.size).select { |i| bytes[i] == '\n'.ord }
          end
          next unless starts.bsearch { |index| index >= site.offset }.try { |index| index < offset }
          append_use(steps, site, :fallback, nil)
        end
      end
      visible = url.delete(JSMountPrefix::UNREAD)
      fallback_scopes.each do |base, site|
        append_use(steps, site, :fallback, site.written) if PrefixScope.prefix_covers?(base, visible)
      end
    end

    private def append_scoped(steps, file, receiver, offset, base, url)
      key = {file, receiver}
      scope = binding_at(key, offset)
      @uses[key]?.try &.each do |site|
        break if site.offset >= offset
        next unless binding_at(key, site.offset) == scope
        if prefix = site.prefix
          next if prefix.includes?(JSMountPrefix::UNREAD) || base.includes?(JSMountPrefix::UNREAD)
          path = URLPath.join(base, prefix)
          if path.ends_with?("/*") || path.ends_with?("/(.*)")
            next unless url.starts_with?(path.rpartition('/')[0] + "/")
          elsif site.verb == "all"
            next unless path.rstrip('/') == url.rstrip('/')
          else
            next unless PrefixScope.prefix_covers?(path, url)
          end
        end
        append_use(steps, site, :router, site.prefix)
      end
    end

    private def append_use(steps, site, origin, prefix)
      site.args.each_with_index do |arg, i|
        steps << RouteMiddleware.new(arg, site.file, origin, i == site.args.size - 1, site.receiver, prefix, site.verb)
      end
    end
  end
end
