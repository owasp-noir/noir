require "../../../models/analyzer"
require "../../engines/go_engine"

module Analyzer::Go
  # Surfaces the command-line attack surface of Go programs as `cli://`
  # endpoints: one endpoint per (sub)command, with named flags/options
  # (param_type "flag"), positional arguments ("argument"), and consumed
  # environment variables ("env"). Covers the stdlib `flag` package +
  # `os.Args` + `os.Getenv`/`os.LookupEnv`, plus the cobra, urfave/cli,
  # pflag, go-arg and go-flags ecosystems.
  #
  # This is a line-scan analyzer (the house style for non-tree-sitter Go
  # adapters, e.g. fasthttp). Endpoints are merged by URL across files so a
  # root command whose flags are registered in a separate `init()` block
  # collects them all under a single `cli://<binary>` entry.
  class Cli < GoEngine
    # Any of these in a file means it participates in the CLI surface.
    FRAMEWORK_IMPORTS = [
      "github.com/spf13/cobra",
      "github.com/urfave/cli",
      "github.com/alexflint/go-arg",
      "github.com/jessevdk/go-flags",
      "github.com/spf13/pflag",
    ]

    # --- builtin flag / argv -------------------------------------------------
    # The flag name is always the FIRST quoted string in the call: the `*Var`
    # forms put the destination pointer (unquoted) first, then the name.
    BUILTIN_FLAG_RE     = /\bflag\.(?:String|Int|Int64|Uint|Uint64|Bool|Float64|Duration)(?:Var)?\s*\(\s*(?:&?[\w.]+\s*,\s*)?"([^"]+)"/
    BUILTIN_FLAG_VAR_RE = /\bflag\.Var\s*\(\s*&?[\w.]+\s*,\s*"([^"]+)"/
    BUILTIN_ARG_RE      = /\bflag\.Arg\s*\(\s*(\d+)\s*\)/
    BUILTIN_ARGS_RE     = /\bflag\.Args\s*\(\s*\)/
    OS_ARG_INDEX_RE     = /\bos\.Args\s*\[\s*(\d+)\s*\]/

    # --- env -----------------------------------------------------------------
    OS_GETENV_RE     = /\bos\.(?:Getenv|LookupEnv)\s*\(\s*"([^"]+)"\s*\)/
    VIPER_BINDENV_RE = /\bviper\.BindEnv\s*\(\s*"([^"]+)"(?:\s*,\s*"([^"]+)")?/

    # --- cobra ---------------------------------------------------------------
    COBRA_CMD_DECL_RE = /(\w+)\s*[:=]\s*&?cobra\.Command\s*\{/
    COBRA_USE_RE      = /\bUse\s*:\s*"([^"\s]+)/
    COBRA_FLAG_RE     = /(\w+)\s*\.\s*(?:Persistent)?Flags\s*\(\s*\)\s*\.\s*[A-Za-z0-9]+\s*\(\s*(?:&?[\w.]+\s*,\s*)?"([^"]+)"/

    # --- pflag (when used without cobra) -------------------------------------
    PFLAG_RE = /\bpflag\.(?:String|Int|Int64|Uint|Bool|Float64|Duration|StringSlice|StringArray)(?:Var)?(?:P)?\s*\(\s*(?:&?[\w.]+\s*,\s*)?"([^"]+)"/

    # --- urfave/cli ----------------------------------------------------------
    URFAVE_APP_RE     = /(?:&)?cli\.App\s*\{/
    URFAVE_CMD_RE     = /(?:&)?cli\.Command\s*\{/
    URFAVE_FLAG_RE    = /(?:&)?cli\.[A-Za-z0-9]*Flag\s*\{/
    URFAVE_NAME_RE    = /\bName\s*:\s*"([^"]+)"/
    URFAVE_ENVVARS_RE = /\bEnvVars\s*:\s*\[\]string\s*\{([^}]*)\}/
    URFAVE_ENVVAR_RE  = /\bEnvVar\s*:\s*"([^"]+)"/

    # --- go-arg / go-flags struct tags ---------------------------------------
    GOARG_TAG_RE    = /`[^`]*\barg:"([^"]*)"[^`]*`/
    GOFLAGS_LONG_RE = /`[^`]*\blong:"([^"]+)"/
    GOFLAGS_ENV_RE  = /`[^`]*\benv:"([^"]+)"/

    # An HTTP listen call in the same file means env reads are most likely
    # server config, not a CLI surface — suppress raw env there.
    HTTP_LISTEN_RE = /\b(?:http|fasthttp)\.ListenAndServe(?:TLS)?\s*\(|\.(?:ListenAndServe|RunTLS)\s*\(/

    def analyze
      modules = collect_go_modules
      endpoints = {} of String => Endpoint

      get_files_by_extension(".go").each do |path|
        next if File.directory?(path)
        next if GoEngine.go_test_file?(path)
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          next unless cli_evidence?(content)

          binary = go_binary_name(modules, path)
          root_url = "cli://#{binary}"
          lines = content.lines
          framework_cli = FRAMEWORK_IMPORTS.any? { |marker| content.includes?(marker) }
          # stdlib flag / os.Args / raw os.Getenv only describe a CLI surface
          # when this file isn't really an HTTP server using flags for config.
          # An explicit CLI framework (cobra/urfave/...) overrides that — a
          # `serve` subcommand legitimately starts a listener.
          emit_stdlib = framework_cli || !content.matches?(HTTP_LISTEN_RE)
          has_cli_parse = cli_parse_point?(content)

          # Map cobra command variables to their command URL.
          cobra_cmd_urls = map_cobra_commands(lines, binary, root_url)

          scan_lines(lines, path, binary, root_url, endpoints, cobra_cmd_urls,
            emit_stdlib, has_cli_parse)
          scan_struct_tags(content, path, root_url, endpoints)
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      endpoints.each_value { |ep| @result << ep }
      @result
    end

    # A file is part of the CLI surface when it imports a CLI framework or
    # uses the stdlib flag package / os.Args directly.
    private def cli_evidence?(content : String) : Bool
      return true if FRAMEWORK_IMPORTS.any? { |m| content.includes?(m) }
      return true if content.includes?("\"flag\"") &&
                     (content.matches?(BUILTIN_FLAG_RE) || content.includes?("flag.Parse(") ||
                     content.matches?(BUILTIN_ARG_RE) || content.matches?(BUILTIN_ARGS_RE))
      content.matches?(OS_ARG_INDEX_RE)
    end

    # A real argv/flag parse point — used to gate raw os.Getenv reads so a
    # web app's config reads don't masquerade as a CLI surface.
    private def cli_parse_point?(content : String) : Bool
      return true if content.includes?("github.com/spf13/cobra")
      return true if content.includes?("github.com/urfave/cli")
      return true if content.includes?("github.com/alexflint/go-arg")
      return true if content.includes?("github.com/jessevdk/go-flags")
      return true if content.includes?("flag.Parse(")
      return true if content.matches?(OS_ARG_INDEX_RE)
      content.includes?("os.Args")
    end

    private def go_binary_name(modules : Array(Tuple(String, String)), path : String) : String
      expanded = File.expand_path(File.dirname(path))
      modules.each do |module_path, module_dir|
        if expanded == module_dir || expanded.starts_with?("#{module_dir}/")
          return File.basename(module_path)
        end
      end
      base = @base_path.empty? ? File.dirname(path) : @base_path
      File.basename(File.expand_path(base))
    end

    # Builds a `cmdVar => url` map for cobra by pairing each
    # `var x = &cobra.Command{` with the `Use:` token inside that same struct
    # literal. A root command (Use token == binary) maps to `cli://<binary>`,
    # every other command to `cli://<binary>/<token>`. A command with no
    # `Use:` field (a common root pattern: only Short/Long/Run) is left
    # unmapped so its flags fall back to the root rather than borrowing a
    # sibling command's Use token.
    private def map_cobra_commands(lines : Array(String), binary : String, root_url : String) : Hash(String, String)
      urls = {} of String => String
      lines.each_with_index do |line, index|
        next unless m = line.match(COBRA_CMD_DECL_RE)
        use_token = find_use_in_struct(lines, index)
        next unless use_token
        urls[m[1]] = use_token == binary ? root_url : "#{root_url}/#{use_token}"
      end
      urls
    end

    # Finds the `Use:` token of the `cobra.Command{...}` struct literal that
    # opens on `start`, bounded by that literal's own braces so a Use-less
    # command can't borrow a sibling's `Use:` declared further down.
    private def find_use_in_struct(lines : Array(String), start : Int32) : String?
      depth = 0
      seen_open = false
      index = start
      while index < lines.size
        line = lines[index]
        if u = line.match(COBRA_USE_RE)
          return u[1]
        end
        line.each_char do |ch|
          if ch == '{'
            depth += 1
            seen_open = true
          elsif ch == '}'
            depth -= 1
          end
        end
        break if seen_open && depth <= 0 # struct literal closed without a Use:
        index += 1
        break if index - start > 60 # safety bound for malformed input
      end
      nil
    end

    # Single forward pass that attributes flags/args/env to the right
    # command, using an inline cursor for urfave literals and the precomputed
    # variable map for cobra.
    private def scan_lines(lines : Array(String), path : String, binary : String,
                           root_url : String, endpoints : Hash(String, Endpoint),
                           cobra_cmd_urls : Hash(String, String),
                           emit_stdlib : Bool, has_cli_parse : Bool)
      urfave_cmd_url = root_url
      urfave_pending : Symbol? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        # cobra command declarations create their endpoint up front so a
        # command with no flags still surfaces.
        if m = line.match(COBRA_CMD_DECL_RE)
          if url = cobra_cmd_urls[m[1]]?
            fetch_endpoint(endpoints, url, path, line_no)
          end
        end

        # cobra flags: receiver var -> mapped command url (fallback root).
        if m = line.match(COBRA_FLAG_RE)
          url = cobra_cmd_urls[m[1]]? || root_url
          ep = fetch_endpoint(endpoints, url, path, line_no)
          ep.push_param(Param.new(m[2], "", "flag"))
        end

        # urfave inline state machine.
        if line.matches?(URFAVE_APP_RE)
          urfave_pending = :app
        elsif line.matches?(URFAVE_CMD_RE)
          urfave_pending = :command
        elsif line.matches?(URFAVE_FLAG_RE)
          urfave_pending = :flag
        end
        if (nm = line.match(URFAVE_NAME_RE)) && urfave_pending
          case urfave_pending
          when :command
            urfave_cmd_url = "#{root_url}/#{nm[1]}"
            fetch_endpoint(endpoints, urfave_cmd_url, path, line_no)
          when :flag
            ep = fetch_endpoint(endpoints, urfave_cmd_url, path, line_no)
            ep.push_param(Param.new(nm[1], "", "flag"))
          when :app
            # App.Name is the binary itself; flags below it bind to root.
            urfave_cmd_url = root_url
          end
          urfave_pending = nil
        end
        if m = line.match(URFAVE_ENVVARS_RE)
          ep = fetch_endpoint(endpoints, urfave_cmd_url, path, line_no)
          m[1].scan(/"([^"]+)"/) { |env| ep.push_param(Param.new(env[1], "", "env")) }
        end
        if m = line.match(URFAVE_ENVVAR_RE)
          ep = fetch_endpoint(endpoints, urfave_cmd_url, path, line_no)
          m[1].split(',').each do |env|
            name = env.strip
            ep.push_param(Param.new(name, "", "env")) unless name.empty?
          end
        end

        # builtin flag / pflag / argv -> root command. Gated by emit_stdlib so
        # an HTTP server that merely uses the flag package for config doesn't
        # surface as a CLI (a real CLI framework lifts the gate).
        if emit_stdlib
          if m = line.match(BUILTIN_FLAG_RE)
            root = fetch_endpoint(endpoints, root_url, path, line_no)
            root.push_param(Param.new(m[1], "", "flag"))
          end
          if m = line.match(BUILTIN_FLAG_VAR_RE)
            root = fetch_endpoint(endpoints, root_url, path, line_no)
            root.push_param(Param.new(m[1], "", "flag"))
          end
          if m = line.match(PFLAG_RE)
            root = fetch_endpoint(endpoints, root_url, path, line_no)
            root.push_param(Param.new(m[1], "", "flag"))
          end
          if m = line.match(BUILTIN_ARG_RE)
            root = fetch_endpoint(endpoints, root_url, path, line_no)
            root.push_param(Param.new("arg#{m[1]}", "", "argument"))
          end
          if line.matches?(BUILTIN_ARGS_RE)
            root = fetch_endpoint(endpoints, root_url, path, line_no)
            root.push_param(Param.new("args", "", "argument"))
          end
          if m = line.match(OS_ARG_INDEX_RE)
            # os.Args[0] is the program name, not an input argument.
            unless m[1] == "0"
              root = fetch_endpoint(endpoints, root_url, path, line_no)
              root.push_param(Param.new("arg#{m[1]}", "", "argument"))
            end
          end
        end

        # viper env binding is framework-bound, always trustworthy.
        if m = line.match(VIPER_BINDENV_RE)
          root = fetch_endpoint(endpoints, root_url, path, line_no)
          env_name = m[2]? || m[1]
          root.push_param(Param.new(env_name, "", "env"))
        end

        # Raw env reads: only in a genuine CLI entry (emit_stdlib already
        # excludes HTTP servers). `scan` so multiple reads on one line all
        # surface.
        if emit_stdlib && has_cli_parse
          line.scan(OS_GETENV_RE) do |env_match|
            root = fetch_endpoint(endpoints, root_url, path, line_no)
            root.push_param(Param.new(env_match[1], "", "env"))
          end
        end
      end
    end

    # go-arg / go-flags declare their surface through struct field tags.
    # Attribute them to the root command (sub-command structs are a v1
    # follow-up).
    private def scan_struct_tags(content : String, path : String, root_url : String,
                                 endpoints : Hash(String, Endpoint))
      return unless content.includes?("alexflint/go-arg") || content.includes?("jessevdk/go-flags")

      content.each_line.with_index do |line, index|
        line_no = index + 1
        if m = line.match(GOARG_TAG_RE)
          parse_goarg_tag(m[1], fetch_endpoint(endpoints, root_url, path, line_no))
        end
        if m = line.match(GOFLAGS_LONG_RE)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(GOFLAGS_ENV_RE)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "env"))
        end
      end
    end

    # Parses a go-arg tag body like `--foo,env:FOO` / `-f` / `positional`.
    private def parse_goarg_tag(tag : String, endpoint : Endpoint)
      tag.split(',').each do |part|
        part = part.strip
        if part.starts_with?("--")
          endpoint.push_param(Param.new(part.lstrip('-'), "", "flag"))
        elsif part.starts_with?("env:")
          endpoint.push_param(Param.new(part.lchop("env:"), "", "env"))
        elsif part == "positional"
          endpoint.push_param(Param.new("args", "", "argument"))
        end
      end
    end

    # Fetches (or lazily creates) the endpoint for a URL, so flags scattered
    # across files/blocks merge onto one command.
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
