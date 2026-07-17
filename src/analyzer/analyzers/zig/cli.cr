require "../../../models/analyzer"

module Analyzer::Zig
  # Surfaces the command-line attack surface of Zig programs as `cli://`
  # endpoints: zig-clap param strings, zig-cli literals, zig-args struct
  # fields, yazap App/Arg builder calls, plus std.process argv / env reads.
  # Line-scan, merged by URL.
  class Cli < Analyzer
    # zig-clap multiline param string lines (each begins with `\\`).
    CLAP_FLAG = /\\\\\s*(?:-[A-Za-z0-9]\s*,\s*)?--([A-Za-z0-9][\w-]*)/
    CLAP_ARG  = /\\\\\s*<([A-Za-z_]\w*)>/
    # zig-cli struct literals. (Only flags are extracted: a `.name` literal is
    # ambiguous between the app name, a subcommand, and a positional-arg name,
    # so subcommand extraction from zig-cli is a follow-up.)
    CLI_LONG = /\.long_name\s*=\s*"(-{0,2}[A-Za-z0-9][\w-]*)"/
    # builtin.
    ARGS_IDX = /\bargs\s*\[\s*(\d+)\s*\]/
    GET_ENV  = /\b(?:std\.process\.getEnvVarOwned\s*\(\s*[\w.]+\s*,\s*"([^"]+)"|(?:std\.)?posix\.getenv\s*\(\s*"([^"]+)")/

    # zig-args: `argsParser.parseForCurrentProcess(Options, allocator, .print)`
    # / `argsParser.parse(Options, &iterator, allocator, .print)`. The
    # receiver MUST be the local alias bound to `@import("args")` (captured
    # via ARGS_IMPORT_ALIAS_RE below) -- otherwise an unrelated `.parse(...)`
    # call on some other receiver (e.g. a URI parser also exposing a `parse`
    # method) could be mistaken for the CLI's option struct. The type name is
    # resolved to its `const <Name> = struct { ... };` declaration (or, for
    # an inline anonymous struct literal, the call site itself) and every
    # top-level field becomes a flag.
    ARGS_IMPORT_ALIAS_RE = /\b(?:pub\s+)?const\s+(\w+)\s*=\s*@import\s*\(\s*"args"\s*\)/
    ARGS_FIELD_RE        = /^\s*([A-Za-z_]\w*)\s*:/

    # yazap: `App.init(...)`, `app.rootCommand()`, `app.createCommand("name", ...)`
    # and `<receiver>.addArg(Arg.positional/booleanOption/singleValueOption(...))`.
    # Receiver variables are mapped to their command URL incrementally, in
    # the SAME forward pass as the addArg scan (see `analyze` below), so a
    # variable reused across subcommands (e.g. a generic `cmd`) resolves to
    # whichever command was assigned to it as of that line, never a
    # whole-file map where a later reassignment retroactively overwrites an
    # earlier addArg's receiver.
    YAZAP_ROOT_RE    = /(\w+)\s*=\s*\w+\.rootCommand\s*\(\s*\)/
    YAZAP_SUBCMD_RE  = /(\w+)\s*=\s*\w+\.createCommand\s*\(\s*"([^"]+)"/
    YAZAP_ADD_ARG_RE = /(\w+)\.addArg\s*\(\s*Arg\.(positional|booleanOption|singleValueOption)\s*\(\s*"([^"]+)"/

    MARKERS = /@import\s*\(\s*"cli"\s*\)|@import\s*\(\s*"clap"\s*\)|@import\s*\(\s*"args"\s*\)|@import\s*\(\s*"yazap"\s*\)|\b(?:std\.)?process\.argsAlloc\s*\(|\bclap\.(?:parseParamsComptime|parse)\b|\bcli\.(?:Command|App|Runner)\b/
    # The subset of MARKERS that is either library-specific API usage or a
    # bare import that pre-dates this file's zig-args/yazap support (kept
    # as-is: an established, non-regressed convention elsewhere in this
    # analyzer). A file matching only via a bare `@import("args")` or
    # `@import("yazap")` -- with no corresponding API call anywhere in the
    # file -- is NOT proof of a CLI surface (a project can vendor an
    # unrelated module that happens to be named "args"), so it must not
    # seed a zero-evidence `cli://<binary>` root endpoint.
    # yazap doesn't need a separate evidence constant here: its bare
    # `@import("yazap")` alone never seeds an endpoint either, because
    # YAZAP_ROOT_RE / YAZAP_SUBCMD_RE / YAZAP_ADD_ARG_RE (used later, in the
    # same forward pass) only call fetch_endpoint when they find a genuine
    # rootCommand/createCommand/addArg call -- so an import with no real
    # yazap usage naturally yields zero endpoints once the root pre-seed
    # below is gated on STRONG_MARKERS.
    STRONG_MARKERS = /@import\s*\(\s*"cli"\s*\)|@import\s*\(\s*"clap"\s*\)|\b(?:std\.)?process\.argsAlloc\s*\(|\bclap\.(?:parseParamsComptime|parse)\b|\bcli\.(?:Command|App|Runner)\b/
    ARGS_IMPORT_RE = /@import\s*\(\s*"args"\s*\)/
    WEB_RE         = /@import\s*\(\s*"(?:zap|jetzig|httpz|tokamak)"\s*\)/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".zig").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)
          binary = cli_binary_name(path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_RE)
          lines = content.each_line.to_a

          # Only pre-seed the root endpoint unconditionally for the
          # established markers; a bare args/yazap import needs the
          # alias/API-usage evidence resolved below first (see
          # STRONG_MARKERS comment above).
          has_strong_marker = content.matches?(STRONG_MARKERS)
          fetch_endpoint(endpoints, root_url, path, 1) if has_strong_marker

          args_alias = content.matches?(ARGS_IMPORT_RE) ? zig_args_alias(lines) : nil
          scan_zig_args(lines, path, root_url, endpoints, args_alias) if args_alias
          yazap_cmd_urls = {} of String => String

          lines.each_with_index do |line, index|
            line_no = index + 1
            # Cheap substring gates before the per-line PCRE2 scans — most
            # source lines never touch clap param strings, yazap builders, or
            # argv/env accessors.
            if line.includes?("\\\\")
              if m = line.match(CLAP_FLAG)
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
              elsif m = line.match(CLAP_ARG)
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].downcase, "", "argument"))
              end
            end
            if line.includes?("long_name") && (m = line.match(CLI_LONG))
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
            end
            if line.includes?("args") && (m = line.match(ARGS_IDX))
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument")) unless m[1] == "0"
            end
            # Update the receiver->URL map for this line BEFORE resolving
            # addArg below, so the map always reflects the state as of the
            # current line (not a whole-file precompute that a later
            # reassignment could retroactively overwrite).
            if line.includes?("rootCommand") && (m = line.match(YAZAP_ROOT_RE))
              yazap_cmd_urls[m[1]] = root_url
            elsif line.includes?("createCommand") && (m = line.match(YAZAP_SUBCMD_RE))
              cmd_url = "#{root_url}/#{m[2]}"
              yazap_cmd_urls[m[1]] = cmd_url
              fetch_endpoint(endpoints, cmd_url, path, line_no)
            end
            if line.includes?("addArg") && (m = line.match(YAZAP_ADD_ARG_RE))
              url = yazap_cmd_urls[m[1]]? || root_url
              ep = fetch_endpoint(endpoints, url, path, line_no)
              param_type = m[2] == "positional" ? "argument" : "flag"
              ep.push_param(Param.new(m[3], "", param_type))
            end
            if emit_env && (line.includes?("getEnvVarOwned") || line.includes?("getenv"))
              line.scan(GET_ENV) do |em|
                name = em[1]? || em[2]?
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "env")) if name
              end
            end
          end
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    # Finds the local identifier bound to `@import("args")`, e.g. `argsParser`
    # in `const argsParser = @import("args");`. Returns nil if the file
    # doesn't declare one (no `@import("args")` evidence to extract from).
    private def zig_args_alias(lines : Array(String)) : String?
      lines.each do |line|
        if m = line.match(ARGS_IMPORT_ALIAS_RE)
          return m[1]
        end
      end
      nil
    end

    # zig-args: locates the Options struct passed to parseForCurrentProcess /
    # parse and surfaces each top-level field as a flag on the root command.
    # Only receivers bound to the file's local `@import("args")` alias
    # (`alias_name`, resolved by the caller via `zig_args_alias`) are
    # honored -- an unbound `.parse(...)` call on some other receiver (e.g.
    # a URI parser also named "parse") is never mistaken for the CLI's
    # option struct. All alias-bound calls are unioned (push_param dedups by
    # name+type) instead of keeping only the first match, so a file with
    # more than one legitimate parse call doesn't silently drop fields from
    # the others.
    private def scan_zig_args(lines : Array(String), path : String, root_url : String,
                              endpoints : Hash(String, Endpoint), alias_name : String)
      named_re = Regex.new("\\b#{Regex.escape(alias_name)}\\.(?:parseForCurrentProcess|parse)\\s*\\(\\s*([A-Za-z_]\\w*)\\s*[,)]")
      inline_re = Regex.new("\\b#{Regex.escape(alias_name)}\\.(?:parseForCurrentProcess|parse)\\s*\\(\\s*struct\\s*\\{")

      lines.each_with_index do |line, index|
        if m = line.match(named_re)
          struct_start = find_struct_start(lines, m[1])
          next unless struct_start
          fields = zig_args_struct_fields(lines, struct_start)
          next if fields.empty?
          ep = fetch_endpoint(endpoints, root_url, path, index + 1)
          fields.each { |f| ep.push_param(Param.new(f, "", "flag")) }
        elsif line.matches?(inline_re)
          fields = zig_args_struct_fields(lines, index)
          next if fields.empty?
          ep = fetch_endpoint(endpoints, root_url, path, index + 1)
          fields.each { |f| ep.push_param(Param.new(f, "", "flag")) }
        end
      end
    end

    # Finds the line index of `const <type_name> = struct {` (optionally
    # `pub`/`packed`/`extern`), scanning the whole file since the type is
    # usually declared above the parse call that references it.
    private def find_struct_start(lines : Array(String), type_name : String) : Int32?
      pattern = Regex.new("\\bconst\\s+#{Regex.escape(type_name)}\\b\\s*=\\s*(?:packed\\s+|extern\\s+)?struct\\s*\\{")
      lines.each_with_index do |line, index|
        return index if line.matches?(pattern)
      end
      nil
    end

    # Collects top-level field names of the struct literal opening on
    # `start_index`, stopping at the matching closing brace so nested blocks
    # (e.g. `pub const shorthands = .{...}`) never contribute a field.
    private def zig_args_struct_fields(lines : Array(String), start_index : Int32) : Array(String)
      fields = [] of String
      depth = 0
      seen_open = false
      index = start_index
      while index < lines.size
        line = lines[index]
        line.each_char do |ch|
          if ch == '{'
            depth += 1
            seen_open = true
          elsif ch == '}'
            depth -= 1
          end
        end
        if seen_open && depth == 1 && (m = line.match(ARGS_FIELD_RE))
          fields << m[1]
        end
        break if seen_open && depth <= 0
        index += 1
        break if index - start_index > 200 # safety bound for malformed input
      end
      fields
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".zig")
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      path.downcase.includes?("/test") || path.includes?("_test.")
    end

    private def fetch_endpoint(endpoints : Hash(String, Endpoint), url : String,
                               path : String, line_no : Int32) : Endpoint
      endpoints[url] ||= begin
        ep = Endpoint.new(url, "CLI", Details.new(PathInfo.new(path, line_no)))
        ep.protocol = "cli"
        ep
      end
    end
  end
end
