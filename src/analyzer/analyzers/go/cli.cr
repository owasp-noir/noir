require "../../../models/analyzer"
require "../../engines/go_engine"
require "../../engines/cli_endpoint_support"
require "../../../utils/top_level_split"
require "../../../utils/js_literal_scanner"

module Analyzer::Go
  # Surfaces the command-line attack surface of Go programs as `cli://`
  # endpoints: one endpoint per (sub)command, with named flags/options
  # (param_type "flag"), positional arguments ("argument"), and consumed
  # environment variables ("env"). Covers the stdlib `flag` package +
  # `os.Args` + `os.Getenv`/`os.LookupEnv`, plus the cobra, urfave/cli,
  # pflag, go-arg, go-flags, kong, kingpin and mitchellh/cli ecosystems.
  #
  # This is a line-scan analyzer (the house style for non-tree-sitter Go
  # adapters, e.g. fasthttp). Endpoints are merged by URL across files so a
  # root command whose flags are registered in a separate `init()` block
  # collects them all under a single `cli://<binary>` entry.
  class Cli < GoEngine
    analyzer_for "go_cli"

    include CliEndpointSupport

    # Any of these in a file means it participates in the CLI surface.
    FRAMEWORK_IMPORTS = [
      "github.com/spf13/cobra",
      "github.com/urfave/cli",
      "github.com/alexflint/go-arg",
      "github.com/jessevdk/go-flags",
      "github.com/spf13/pflag",
      "github.com/alecthomas/kong",
      "github.com/mitchellh/cli",
      "github.com/alecthomas/kingpin",
      "gopkg.in/alecthomas/kingpin.v2",
    ]
    # `FRAMEWORK_IMPORTS.any? { |m| content.includes?(m) }` re-scans the
    # whole file once per marker (used at two call sites below); one
    # precompiled `Regex.union` (PCRE2 JIT) checks all nine in a single pass.
    FRAMEWORK_IMPORTS_RE = Regex.union(FRAMEWORK_IMPORTS)

    # Cheap pre-gate applied to the RAW file, before the comment strip.
    #
    # `GoEngine.strip_comments` materialises an `Array(Char)` of the whole
    # file and rebuilds it character by character; running it on every
    # `.go` file in a monorepo — 15k of them in kubernetes, of which a
    # couple of hundred have any CLI surface — was the whole cost of this
    # analyzer. Stripping only ever replaces characters with `' '` or
    # `'\n'` and never changes the character count, so a literal with no
    # whitespace in it can appear in the stripped text only if it already
    # appears, unchanged, in the raw text. Every branch of `cli_evidence?`
    # requires one of these literals verbatim (`FLAG_IMPORT_RE` is the
    # literal `"flag"`; `OS_ARG_INDEX_RE` needs an adjacent `os.Args`), so
    # a file that misses all of them cannot pass `cli_evidence?` after the
    # strip either. Files that do match still go through the full,
    # comment-aware gate below.
    RAW_CLI_EVIDENCE_RE = Regex.union(FRAMEWORK_IMPORTS + [%("flag"), "os.Args"])

    # Per-framework matchers for the scan dispatch below, which asks the
    # same questions again once `cli_evidence?` has let a file through.
    KONG_IMPORT_RE       = Regex.union("github.com/alecthomas/kong")
    KINGPIN_IMPORT_RE    = Regex.union("github.com/alecthomas/kingpin", "gopkg.in/alecthomas/kingpin.v2")
    MITCHELLH_IMPORT_RE  = Regex.union("github.com/mitchellh/cli")
    STRUCT_TAG_IMPORT_RE = Regex.union("alexflint/go-arg", "jessevdk/go-flags")
    FLAG_IMPORT_RE       = /"flag"/
    FLAG_PARSE_RE        = /flag\.Parse\(/
    OS_ARGS_RE           = /os\.Args/

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
    # `var x = &cobra.Command{` / `x := ...` / `x = ...` / a `Cmd: ...` field.
    COBRA_CMD_DECL_RE = /(?:\b(var)\s+)?\b(\w+)\s*(:=|=|:)\s*&?cobra\.Command\s*\{/
    COBRA_USE_RE      = /\bUse\s*:\s*"([^"\s]+)/
    COBRA_FLAG_RE     = /(\w+)\s*\.\s*(?:Persistent)?Flags\s*\(\s*\)\s*\.\s*[A-Za-z0-9]+\s*\(\s*(?:&?[\w.]+\s*,\s*)?"([^"]+)"/
    COBRA_IMPORT_RE   = Regex.union("github.com/spf13/cobra")
    COBRA_ADD_CMD_RE  = /\b(\w+)\s*\.\s*AddCommand\s*\(/
    COBRA_EXECUTE_RE  = /\b(\w+)\s*\.\s*Execute(?:C|Context|ContextC)?\s*\(/
    # An `AddCommand` argument naming a command: `serveCmd` or `serve.Cmd`.
    # A call (`newServeCmd()`) names none.
    GO_REF_RE       = /\A(?:(\w+)\s*\.\s*)?(\w+)\z/
    GO_CALL_REF_RE  = /\A(?:(\w+)\s*\.\s*)?(\w+)\s*\(/
    GO_QUALIFIER_RE = /(\w+)\s*\.\s*\z/
    GO_FUNC_RE      = /^func\s+(?:\([^)]*\)\s*)?(\w+)\s*[\[(]/
    # A constructor's result: `return &cobra.Command{...}` or `return cmd`.
    COBRA_RETURN_CMD_RE = /\breturn\s+&?cobra\.Command\s*\{/
    RETURN_REF_RE       = /\breturn\s+(\w+)\s*(?:,|$)/
    CALL_ARG_RULES      = Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll)

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

    # A bare unindented `}` closes the top-level struct/func block it
    # belongs to (the gofmt convention this line-scan relies on for
    # kong's `type X struct {}` and mitchellh/cli's `func (...) Run(...) {}`
    # scoping below).
    TOPLEVEL_BRACE_CLOSE_RE = /^\}\s*$/

    # A wrapped call is matched as one logical line (see `call_lines`); this
    # caps how many continuation lines one call may pull in.
    MAX_CALL_CONTINUATION = 8
    # `var (` / `const (` / `import (` open a block, not a call.
    PAREN_BLOCK_RE = /^\s*(?:var|const|import|type)\s*\($/

    # --- kong (struct-tag CLI) ------------------------------------------------
    # Root/subcommand fields are declared as struct fields; a `cmd:""` tag
    # marks a field as a subcommand whose own flags/args live in that
    # field's named struct type, an `arg:""` tag marks a positional, and an
    # `env:""` tag additionally binds the field to an environment variable.
    KONG_TYPE_DECL_RE = /^type\s+(\w+)\s+struct\s*\{/
    KONG_FIELD_RE     = /^\s*([A-Z]\w*)\s+([\w.\[\]*]+)\s+`([^`]*)`/
    KONG_TAG_KEY_RE   = /\b(?:cmd|arg|env|default|help)\s*:\s*"/
    KONG_CMD_TAG_RE   = /\bcmd\s*:\s*"[^"]*"/
    KONG_ARG_TAG_RE   = /\barg\s*:\s*"[^"]*"/
    KONG_ENV_TAG_RE   = /\benv\s*:\s*"([^"]+)"/
    KONG_NAME_TAG_RE  = /\bname\s*:\s*"([^"]+)"/

    # --- kingpin (fluent Flag/Arg/Command builder) ---------------------------
    # `app := kingpin.New(...)` seeds the root receiver; `cmd := app.Command(...)`
    # (or `sub := cmd.Command(...)` for nesting) maps a new receiver var onto
    # a command URL, and `.Flag(...)`/`.Arg(...)` calls on a *known* receiver
    # attribute a param to that command — never to a sticky "current" command.
    KINGPIN_NEW_RE     = /(\w+)\s*:?=\s*kingpin\.New\s*\(/
    KINGPIN_COMMAND_RE = /(\w+)\s*:?=\s*(\w+)\s*\.\s*Command\s*\(\s*"([^"]+)"/
    KINGPIN_FLAG_RE    = /(\w+)\s*\.\s*Flag\s*\(\s*"([^"]+)"\s*,/
    KINGPIN_ARG_RE     = /(\w+)\s*\.\s*Arg\s*\(\s*"([^"]+)"\s*,/
    KINGPIN_ENVAR_RE   = /\.\s*Envar\s*\(\s*"([^"]+)"\s*\)/

    # --- mitchellh/cli (Commands map of factories) ----------------------------
    # `c.Commands = map[string]cli.CommandFactory{"name": func() (cli.Command,
    # error) { return &FooCommand{}, nil }}` maps each map key to the
    # concrete command type it instantiates; that type's own `Run` method is
    # then scanned (scoped to its own body) for `flag.FlagSet`-style
    # `*Var` registrations and raw env reads.
    MITCHELLH_KEY_RE    = /^\s*"([^"]+)"\s*:\s*func\s*\(\s*\)\s*\(cli\.Command,\s*error\)\s*\{/
    MITCHELLH_RETURN_RE = /return\s+&(\w+)\{/
    # `cmd := &DeployCommand{}` followed later (within the SAME closure) by
    # `return cmd, nil` — the idiomatic form used whenever the command needs
    # field initialization, as common as the single-expression `return &X{}`.
    MITCHELLH_VAR_ASSIGN_RE = /(\w+)\s*:=\s*&(\w+)\{/
    MITCHELLH_RETURN_VAR_RE = /return\s+(\w+)\s*,/
    MITCHELLH_RUN_FUNC_RE   = /^func\s*\(\s*\w+\s+\*?(\w+)\)\s*Run\s*\(/
    MITCHELLH_FLAGVAR_RE    = /\b\w+\.(?:StringVar|IntVar|Int64Var|BoolVar|Float64Var|DurationVar)\s*\(\s*&?[\w.]+\s*,\s*"([^"]+)"/

    # An HTTP listen call in the same file means env reads are most likely
    # server config, not a CLI surface — suppress raw env there.
    HTTP_LISTEN_RE = /\b(?:http|fasthttp)\.ListenAndServe(?:TLS)?\s*\(|\.(?:ListenAndServe|RunTLS)\s*\(/

    def analyze
      modules = collect_go_modules
      endpoints = {} of String => Endpoint

      sources = [] of Tuple(String, String, Array(String), Array(String))
      get_files_by_extension(".go").each do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)

        begin
          # Blank out comments before any matching: the flag/command
          # patterns below are shape-based, so a commented-out or merely
          # documented registration read as a live one. Line numbers are
          # preserved, so PathInfo stays accurate.
          raw = read_file_content(path)
          next unless content_matches?(raw, RAW_CLI_EVIDENCE_RE)
          content = GoEngine.strip_comments(raw)
          next unless cli_evidence?(content)

          lines = content.lines
          sources << {path, content, lines, call_lines(lines)}
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      cobra = build_cobra_tree(sources, modules)

      sources.each do |path, content, lines, calls|
        binary = cobra_package_binary(cobra, go_package_dir(path))
        root_url = "cli://#{binary}"
        framework_cli = content.matches?(FRAMEWORK_IMPORTS_RE)
        # stdlib flag / os.Args / raw os.Getenv only describe a CLI surface
        # when this file isn't really an HTTP server using flags for config.
        # An explicit CLI framework (cobra/urfave/...) overrides that — a
        # `serve` subcommand legitimately starts a listener.
        emit_stdlib = framework_cli || !content.matches?(HTTP_LISTEN_RE)
        has_cli_parse = cli_parse_point?(content)

        scan_lines(calls, path, binary, root_url, endpoints, cobra,
          emit_stdlib, has_cli_parse)
        scan_struct_tags(content, path, root_url, endpoints)

        if content_matches?(content, KONG_IMPORT_RE)
          scan_kong(lines, path, root_url, endpoints, kong_cmd_type_urls(lines, root_url))
        end

        if content_matches?(content, KINGPIN_IMPORT_RE)
          scan_kingpin(calls, path, endpoints, kingpin_cmd_urls(calls, root_url))
        end

        if content_matches?(content, MITCHELLH_IMPORT_RE)
          scan_mitchellh(lines, calls, path, root_url, endpoints)
        end
      rescue e
        logger.debug "Error analyzing #{path}: #{e}"
        next
      end

      @result.concat(cli_endpoints(endpoints))
      @result
    end

    # `lines`, with each call whose arguments wrap joined onto its first line:
    # `Flags().IntVar(&port,` + `"port", 0, "")` or a kingpin chain broken
    # after a `.` would otherwise lose the name (or `.Envar(...)`) on the
    # next line. A line opens such a call when it leaves a `(` unclosed and
    # ends in `(` or `,`, or ends in `.`. Every index keeps its own line too,
    # so line numbers and brace-scoped scans are unchanged.
    private def call_lines(lines : Array(String)) : Array(String)
      lines.map_with_index do |line, index|
        tail = line.rstrip
        depth = line.count('(') - line.count(')')
        next line unless tail.ends_with?('.') || (depth > 0 && (tail.ends_with?('(') || tail.ends_with?(',')))
        next line if tail.matches?(PAREN_BLOCK_RE)
        String.build do |io|
          io << tail
          (index + 1).upto(Math.min(index + MAX_CALL_CONTINUATION, lines.size - 1)) do |j|
            tail = lines[j].strip
            io << ' ' << tail
            depth += tail.count('(') - tail.count(')')
            break if depth <= 0 && !tail.ends_with?('.')
          end
        end
      end
    end

    # A file is part of the CLI surface when it imports a CLI framework or
    # uses the stdlib flag package / os.Args directly.
    private def cli_evidence?(content : String) : Bool
      return true if content_matches?(content, FRAMEWORK_IMPORTS_RE)
      return true if content_matches?(content, FLAG_IMPORT_RE) &&
                     (content_matches?(content, BUILTIN_FLAG_RE) || content_matches?(content, FLAG_PARSE_RE) ||
                     content_matches?(content, BUILTIN_ARG_RE) || content_matches?(content, BUILTIN_ARGS_RE))
      content_matches?(content, OS_ARG_INDEX_RE)
    end

    # Five markers OR-ed as a standalone boolean gate for `cli_parse_point?`
    # below — one precompiled `Regex.union` (PCRE2 JIT) replaces the
    # separate `content.includes?` scan each used to make over the same
    # buffer. kong/kingpin/mitchellh are deliberately excluded (see the
    # comment in `cli_parse_point?`).
    CLI_PARSE_POINT_RE = Regex.union(
      "github.com/spf13/cobra",
      "github.com/urfave/cli",
      "github.com/alexflint/go-arg",
      "github.com/jessevdk/go-flags",
      "flag.Parse(",
    )

    # A real argv/flag parse point — used to gate raw os.Getenv reads so a
    # web app's config reads don't masquerade as a CLI surface.
    private def cli_parse_point?(content : String) : Bool
      # kong/kingpin/mitchellh's own scans attribute their env vars
      # precisely (struct tag / .Envar() / scoped Run() body) — they
      # deliberately don't opt into the raw root-level os.Getenv fallback
      # below, which would double-attribute (or mis-scope) those reads.
      return true if content_matches?(content, CLI_PARSE_POINT_RE)
      return true if content_matches?(content, OS_ARG_INDEX_RE)
      content_matches?(content, OS_ARGS_RE)
    end

    # A Go module can hold many commands — `cmd/foo`, `services/bar/cmd` —
    # and each `package main` directory is a separate binary. Naming every
    # one of them after the module merged unrelated programs' flags into a
    # single `cli://<module>` endpoint. Library packages keep the module
    # name, so the cross-file merge this analyzer is built around still
    # works for the helper files a command pulls its flags from.
    PACKAGE_MAIN_RE = /^\s*package\s+main\b/m

    private def go_binary_name(modules : Array(Tuple(String, String)), path : String, content : String) : String
      expanded = Noir::PathScope.expand(File.dirname(path))
      modules.each do |module_path, module_dir|
        if expanded == module_dir || expanded.starts_with?("#{module_dir}/")
          if expanded != module_dir && content.matches?(PACKAGE_MAIN_RE)
            if name = cli_directory_binary_name(path)
              return name
            end
          end
          return File.basename(module_path)
        end
      end
      base = @base_path.empty? ? File.dirname(path) : @base_path
      File.basename(Noir::PathScope.expand(base))
    end

    # The cobra command trees of a scan. A command is identified by where it
    # is declared (`path:line`), not by its variable name: two constructors
    # that each say `get := &cobra.Command{...}` declare two commands, and a
    # reference resolves the way Go scoping does — the innermost local in
    # the file, then the package-level variable of its package (shared by all
    # the package's files), or `pkg.Var` through the file's imports. A
    # constructor (`func newLsCmd() *cobra.Command`) stands for the command
    # it returns, so `cmd.AddCommand(newLsCmd())` links too.
    private class CobraTree
      getter uses = {} of String => String                       # id => Use token
      getter parents = {} of String => String                    # child id => parent id
      getter executed = Set(String).new                          # ids whose Execute*() is called
      getter dirs = {} of String => String                       # id => package directory
      getter package_vars = {} of String => Hash(String, String) # dir => package-level var => id
      getter constructors = {} of String => Hash(String, String) # dir => func name => returned id
      getter decl_lines = {} of String => Hash(Int32, String)    # path => line index => declared id
      getter flag_lines = {} of String => Hash(Int32, String)    # path => line index => flag receiver id
      getter packages = {} of String => Tuple(String, String)    # dir => {a path, its content}
      getter binaries = {} of String => String                   # dir => binary name
      getter urls = {} of String => String                       # id => url
      getter modules : Array(Tuple(String, String))

      def initialize(@modules)
      end
    end

    private def build_cobra_tree(sources : Array(Tuple(String, String, Array(String), Array(String))),
                                 modules : Array(Tuple(String, String))) : CobraTree
      tree = CobraTree.new(modules)
      cobra_sources = [] of Tuple(String, String, Array(String), Array(String), Array(Int32))

      # Declarations first, so a package-level command declared in `root.go`
      # is known when `serve.go` adds a child to it.
      sources.each do |path, content, lines, calls|
        dir = go_package_dir(path)
        tree.packages[dir] ||= {path, content}
        next unless content_matches?(content, COBRA_IMPORT_RE)

        depths = brace_depths(lines)
        cobra_sources << {path, content, lines, calls, depths}
        decls = tree.decl_lines[path] = {} of Int32 => String
        vars = tree.package_vars[dir] ||= {} of String => String
        constructors = tree.constructors[dir] ||= {} of String => String
        func_name : String? = nil
        lines.each_with_index do |line, index|
          if depths[index] == 0 && (fm = line.match(GO_FUNC_RE))
            func_name = fm[1]
          end
          m = line.match(COBRA_CMD_DECL_RE)
          returned = !m && line.matches?(COBRA_RETURN_CMD_RE)
          next unless m || returned
          id = "#{path}:#{index}"
          decls[index] = id
          tree.dirs[id] = dir
          if use_token = find_use_in_struct(lines, index)
            tree.uses[id] = use_token
          end
          if m
            # Top level, or a bare `x = &cobra.Command{` in a function body
            # assigning the package variable (`var rootCmd *cobra.Command`
            # filled in by `init`).
            vars[m[2]] = id if depths[index] == 0 || (m[3] == "=" && !m[1]? && !vars.has_key?(m[2]))
          elsif name = func_name
            constructors[name] ||= id
          end
        end
      end

      # Constructor calls resolve once every file has said what it returns.
      pending = [] of Tuple(String, String, String) # {parent id, constructor dir, func name}
      cobra_sources.each do |path, content, lines, calls, depths|
        link_cobra_file(tree, path, content, lines, calls, depths, pending)
      end
      pending.each do |parent, dir, name|
        child = tree.constructors[dir]?.try(&.[name]?)
        tree.parents[child] = parent if child && child != parent
      end
      tree
    end

    # Brace depth at the start of each line.
    private def brace_depths(lines : Array(String)) : Array(Int32)
      depth = 0
      lines.map do |line|
        start = depth
        depth += line.count('{') - line.count('}')
        start
      end
    end

    # One forward pass over a cobra file that resolves every command
    # reference (flag receiver, `AddCommand` parent and children, `Execute`
    # receiver) to the declaration it names at that point.
    private def link_cobra_file(tree : CobraTree, path : String, content : String, lines : Array(String),
                                calls : Array(String), depths : Array(Int32),
                                pending : Array(Tuple(String, String, String)))
      dir = go_package_dir(path)
      constructors = tree.constructors[dir]
      decls = tree.decl_lines[path]
      flags = tree.flag_lines[path] = {} of Int32 => String
      locals = {} of String => Array(Tuple(String, Int32)) # var => [{id, scope depth}], innermost last
      aliases = [] of Hash(String, String)                 # parsed on the first `pkg.Var` reference

      import_of = ->(qualifier : String?) : String? {
        return unless qualifier
        aliases << Noir::GoCalleeExtractor.extract_import_aliases(content) if aliases.empty?
        aliases.first[qualifier]?
      }
      resolve = ->(qualifier : String?, var : String) : String? {
        if import_path = import_of.call(qualifier)
          target = go_import_dir(import_path, tree.modules)
          return target ? tree.package_vars[target]?.try(&.[var]?) : nil
        end
        locals[var]?.try(&.last?).try(&.[0]) || tree.package_vars[dir]?.try(&.[var]?)
      }

      previous_depth = 0
      func_name : String? = nil
      lines.each_index do |index|
        depth = depths[index]
        if depth == 0 && (fm = lines[index].match(GO_FUNC_RE))
          func_name = fm[1]
        end
        # A block closed: its locals go out of scope.
        locals.each_value { |stack| stack.reject! { |(_id, scope)| scope > depth } } if depth < previous_depth
        previous_depth = depth

        if (id = decls[index]?) && depth > 0 && (m = lines[index].match(COBRA_CMD_DECL_RE))
          (locals[m[2]] ||= [] of Tuple(String, Int32)) << {id, depth} if m[3] != "=" || m[1]?
        end

        call = calls[index]
        if (m = call.match(COBRA_FLAG_RE)) && (id = resolve.call(go_qualifier(call, m.byte_begin(1)), m[1]))
          flags[index] = id
        end
        call.scan(COBRA_ADD_CMD_RE) do |am|
          next unless parent = resolve.call(go_qualifier(call, am.byte_begin(1)), am[1])
          cobra_call_args(call, am.byte_end(0) - 1).each do |arg|
            if ref = arg.match(GO_REF_RE)
              child = resolve.call(ref[1]?, ref[2])
              tree.parents[child] = parent if child && child != parent
            elsif ref = arg.match(GO_CALL_REF_RE)
              # `newLsCmd(...)` / `configcmd.NewCommand(...)`; a method call
              # (`o.newCmd()`) is looked up in this package.
              import_path = import_of.call(ref[1]?)
              target = import_path ? go_import_dir(import_path, tree.modules) : dir
              pending << {parent, target, ref[2]} if target
            end
          end
        end
        if (name = func_name) && (rm = lines[index].match(RETURN_REF_RE)) && (id = resolve.call(nil, rm[1]))
          constructors[name] ||= id
        end
        call.scan(COBRA_EXECUTE_RE) do |em|
          if id = resolve.call(go_qualifier(call, em.byte_begin(1)), em[1])
            tree.executed << id
          end
        end
      end
    end

    # The `pkg` of `pkg.name` when `name` starts at byte `name_start`.
    private def go_qualifier(call : String, name_start : Int32) : String?
      return if name_start == 0
      call.byte_slice(0, name_start).match(GO_QUALIFIER_RE).try(&.[1])
    end

    # The top-level arguments of the call whose `(` is at byte `open_paren`.
    private def cobra_call_args(call : String, open_paren : Int32) : Array(String)
      close = Noir::JSLiteralScanner.find_matching_paren_at_byte(call, open_paren) || call.bytesize
      Noir::TopLevelSplit.split(call.byte_slice(open_paren + 1, close - open_paren - 1), ',', CALL_ARG_RULES)
    end

    private def go_package_dir(path : String) : String
      Noir::PathScope.expand(File.dirname(path))
    end

    # The directory of an import path inside one of the scanned modules.
    private def go_import_dir(import_path : String, modules : Array(Tuple(String, String))) : String?
      modules.each do |module_path, module_dir|
        return module_dir if import_path == module_path
        return "#{module_dir}#{import_path[module_path.size..]}" if import_path.starts_with?("#{module_path}/")
      end
      nil
    end

    # The binary a package's commands belong to.
    #
    # A `package main` is the binary `go build` produces, named after its
    # directory. A library package (`cmd/alpha/command`) has no binary name
    # of its own — the path gives only the module name, which merged two
    # binaries of one module — so it takes the `Use` of its root: the one
    # executed command that no `AddCommand` adopts. A package whose commands
    # are adopted by another package's tree takes that tree's binary.
    private def cobra_package_binary(tree : CobraTree, dir : String, seen = Set(String).new) : String
      if binary = tree.binaries[dir]?
        return binary
      end
      path, content = tree.packages[dir]
      binary = nil
      if seen.add?(dir) && !content.matches?(PACKAGE_MAIN_RE)
        roots = tree.executed.select { |id| tree.dirs[id] == dir && tree.uses.has_key?(id) && !tree.parents.has_key?(id) }
        binary = tree.uses[roots.first] if roots.size == 1
        unless binary
          tree.parents.each do |child, parent|
            next unless tree.dirs[child] == dir
            top_dir = tree.dirs[cobra_chain(tree, parent).last]
            next if top_dir == dir
            binary = cobra_package_binary(tree, top_dir, seen)
            break
          end
        end
      end
      tree.binaries[dir] = binary || go_binary_name(tree.modules, path, content)
    end

    # `id` and its ancestors, nearest first, stopping before a cycle repeats.
    private def cobra_chain(tree : CobraTree, id : String) : Array(String)
      chain = [id]
      while (parent = tree.parents[chain.last]?) && !chain.includes?(parent)
        chain << parent
      end
      chain
    end

    # A command's URL is its ancestors' Use tokens under its binary. A
    # parentless command is the root (`cli://<binary>`) when it is executed
    # or its Use token is the binary, and a direct child of the root
    # otherwise (it may be added from code this scan can't link). A Use-less
    # command (a common root: only Short/Run) adds no segment.
    private def cobra_url(tree : CobraTree, id : String) : String
      tree.urls[id] ||= begin
        chain = cobra_chain(tree, id)
        top = chain.last
        binary = cobra_package_binary(tree, tree.dirs[top])
        url = "cli://#{binary}"
        if (use_token = tree.uses[top]?) && use_token != binary && !tree.executed.includes?(top)
          url += "/#{use_token}"
        end
        chain.reverse_each.skip(1).each do |ancestor|
          if use_token = tree.uses[ancestor]?
            url += "/#{use_token}"
          end
        end
        url
      end
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
    # command, using an inline cursor for urfave literals and the resolved
    # cobra tree for cobra.
    private def scan_lines(lines : Array(String), path : String, binary : String,
                           root_url : String, endpoints : Hash(String, Endpoint),
                           cobra : CobraTree,
                           emit_stdlib : Bool, has_cli_parse : Bool)
      urfave_cmd_url = root_url
      cobra_decls = cobra.decl_lines[path]?
      cobra_flags = cobra.flag_lines[path]?
      urfave_pending : Symbol? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        # cobra command declarations create their endpoint up front so a
        # command with no flags still surfaces.
        if (id = cobra_decls.try(&.[index]?)) && cobra.uses.has_key?(id)
          fetch_endpoint(endpoints, cobra_url(cobra, id), path, line_no)
        end

        # cobra flags: receiver -> its command's url (fallback root).
        if m = line.match(COBRA_FLAG_RE)
          id = cobra_flags.try(&.[index]?)
          url = id ? cobra_url(cobra, id) : root_url
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
            # urfave/cli v1 packs short aliases into the name ("config, c");
            # the optimizer drops params whose name contains a space, so keep
            # only the canonical first token.
            ep.push_param(Param.new(nm[1].split(',').first.strip, "", "flag"))
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
      return unless content_matches?(content, STRUCT_TAG_IMPORT_RE)

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

    # --- kong ------------------------------------------------------------------

    # Converts an exported Go field name into kong's default kebab-case
    # flag/command label (e.g. "ApiToken" -> "api-token"). An explicit
    # `name:"..."` tag always wins over this derivation.
    private def kong_kebab(name : String) : String
      String.build do |sb|
        name.each_char_with_index do |ch, i|
          sb << '-' if ch.uppercase? && i > 0
          sb << ch.downcase
        end
      end
    end

    private def kong_field_label(field_name : String, tag : String) : String
      if nm = tag.match(KONG_NAME_TAG_RE)
        nm[1]
      else
        kong_kebab(field_name)
      end
    end

    # Kong subcommand fields are frequently pointer-typed (`Serve *ServeCmd
    # `cmd:""``, a common idiom for optional subcommands) as well as
    # value-typed (`Serve ServeCmd `cmd:""``). Strip the leading `*` so both
    # forms resolve to the same type-map key as the `type ServeCmd struct {`
    # declaration itself (which never carries a pointer sigil).
    private def kong_strip_ptr(type_name : String) : String
      type_name.starts_with?('*') ? type_name[1..] : type_name
    end

    # Maps each `cmd:""`-tagged field's struct TYPE to its command URL, so
    # the fields declared inside that type's own `type Foo struct {}` block
    # (scanned separately below) attribute onto the right subcommand instead
    # of the root.
    private def kong_cmd_type_urls(lines : Array(String), root_url : String) : Hash(String, String)
      urls = {} of String => String
      lines.each do |line|
        next unless m = line.match(KONG_FIELD_RE)
        tag = m[3]
        next unless tag.matches?(KONG_CMD_TAG_RE)
        urls[kong_strip_ptr(m[2])] = "#{root_url}/#{kong_field_label(m[1], tag)}"
      end
      urls
    end

    # Single forward pass, scoped by the unindented `type Foo struct {` /
    # `}` pair currently open (nil means "inside the root CLI struct").
    #
    # A struct whose name never appears as a `cmd:""`-tagged field's type is
    # NOT part of the kong CLI tree — it's some other library's struct that
    # merely happens to share a common tag key (env/default/help are also
    # used by envconfig, cleanenv, etc.). Such fields are dropped entirely
    # rather than falling back to the root command, so an unrelated config
    # struct can never contaminate `cli://<binary>`.
    private def scan_kong(lines : Array(String), path : String, root_url : String,
                          endpoints : Hash(String, Endpoint), type_urls : Hash(String, String))
      current_type : String? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        if m = line.match(KONG_TYPE_DECL_RE)
          current_type = m[1]
          if url = type_urls[current_type]?
            fetch_endpoint(endpoints, url, path, line_no)
          end
          next
        end
        if current_type && line.matches?(TOPLEVEL_BRACE_CLOSE_RE)
          current_type = nil
          next
        end

        next unless m = line.match(KONG_FIELD_RE)
        tag = m[3]
        next unless tag.matches?(KONG_TAG_KEY_RE)

        if current_type
          next unless scope_url = type_urls[current_type]?
        else
          scope_url = root_url
        end

        if tag.matches?(KONG_CMD_TAG_RE)
          fetch_endpoint(endpoints, type_urls[kong_strip_ptr(m[2])]? || scope_url, path, line_no)
        elsif tag.matches?(KONG_ARG_TAG_RE)
          ep = fetch_endpoint(endpoints, scope_url, path, line_no)
          ep.push_param(Param.new(kong_field_label(m[1], tag), "", "argument"))
        else
          ep = fetch_endpoint(endpoints, scope_url, path, line_no)
          ep.push_param(Param.new(kong_field_label(m[1], tag), "", "flag"))
        end

        if em = tag.match(KONG_ENV_TAG_RE)
          ep = fetch_endpoint(endpoints, scope_url, path, line_no)
          ep.push_param(Param.new(em[1], "", "env"))
        end
      end
    end

    # --- kingpin -----------------------------------------------------------------

    # Maps every receiver variable that is genuinely part of the kingpin
    # chain (the root `app` plus every `Command(...)`-declared subcommand)
    # onto its command URL. Built as two forward passes so a subcommand can
    # itself parent a nested subcommand declared further down the file.
    private def kingpin_cmd_urls(lines : Array(String), root_url : String) : Hash(String, String)
      urls = {} of String => String
      lines.each do |line|
        if m = line.match(KINGPIN_NEW_RE)
          urls[m[1]] = root_url
        end
      end
      lines.each do |line|
        next unless m = line.match(KINGPIN_COMMAND_RE)
        next unless parent_url = urls[m[2]]?
        urls[m[1]] = "#{parent_url}/#{m[3]}"
      end
      urls
    end

    # Flags/args only attribute when their receiver is a *known* kingpin
    # var (root app or a mapped command) — never a sticky "last command".
    private def scan_kingpin(lines : Array(String), path : String,
                             endpoints : Hash(String, Endpoint), cmd_urls : Hash(String, String))
      lines.each_with_index do |line, index|
        line_no = index + 1

        if m = line.match(KINGPIN_COMMAND_RE)
          if url = cmd_urls[m[1]]?
            fetch_endpoint(endpoints, url, path, line_no)
          end
        end

        if m = line.match(KINGPIN_FLAG_RE)
          if url = cmd_urls[m[1]]?
            ep = fetch_endpoint(endpoints, url, path, line_no)
            ep.push_param(Param.new(m[2], "", "flag"))
            if em = line.match(KINGPIN_ENVAR_RE)
              ep.push_param(Param.new(em[1], "", "env"))
            end
          end
        end

        if m = line.match(KINGPIN_ARG_RE)
          if url = cmd_urls[m[1]]?
            ep = fetch_endpoint(endpoints, url, path, line_no)
            ep.push_param(Param.new(m[2], "", "argument"))
          end
        end
      end
    end

    # --- mitchellh/cli -----------------------------------------------------------

    # Maps each command factory's concrete return type (e.g. `&DeployCommand{}`)
    # to its command URL, keyed off the map literal's own string key. Each
    # key's return type is resolved by a search strictly SCOPED to that
    # factory closure's own brace-tracked body — never a global "last seen"
    # cursor — so a closure whose return type can't be resolved (or that
    # returns via an intermediate variable declared in an unusual way) is
    # simply abandoned instead of leaking into unrelated code later in the
    # file.
    private def mitchellh_cmd_type_urls(lines : Array(String), root_url : String) : Hash(String, String)
      urls = {} of String => String
      lines.each_with_index do |line, index|
        next unless m = line.match(MITCHELLH_KEY_RE)
        key = m[1]
        if return_type = resolve_mitchellh_factory_return_type(lines, index)
          urls[return_type] = "#{root_url}/#{key}"
        end
      end
      urls
    end

    # Scans forward from a CommandFactory closure's opening line (the
    # `"key": func() (cli.Command, error) {` line), bounded by that
    # closure's own matching `}`, for the concrete command type it returns —
    # either directly (`return &X{}, nil`) or via an intermediate variable
    # (`cmd := &X{}` ... `return cmd, nil`, an idiomatic pattern whenever the
    # command needs field initialization). Returns nil (never a fallback)
    # if the closure closes without a resolvable return.
    private def resolve_mitchellh_factory_return_type(lines : Array(String), start : Int32) : String?
      depth = 0
      local_vars = {} of String => String
      index = start

      while index < lines.size
        line = lines[index]

        if m = line.match(MITCHELLH_RETURN_RE)
          return m[1]
        end
        if m = line.match(MITCHELLH_VAR_ASSIGN_RE)
          local_vars[m[1]] = m[2]
        end
        if m = line.match(MITCHELLH_RETURN_VAR_RE)
          if t = local_vars[m[1]]?
            return t
          end
        end

        line.each_char do |ch|
          depth += 1 if ch == '{'
          depth -= 1 if ch == '}'
        end
        break if depth <= 0 && index > start # closure closed, nothing resolved
        index += 1
        break if index - start > 200 # safety bound for malformed input
      end
      nil
    end

    private def mitchellh_cmd_keys(lines : Array(String)) : Array(Tuple(String, Int32))
      keys = [] of Tuple(String, Int32)
      lines.each_with_index do |line, index|
        if m = line.match(MITCHELLH_KEY_RE)
          keys << {m[1], index + 1}
        end
      end
      keys
    end

    # Every map key becomes an endpoint up front (a command with no flags of
    # its own still surfaces), then a second pass scoped to each mapped
    # type's own `Run` method body picks up FlagSet `*Var` registrations and
    # raw env reads.
    private def scan_mitchellh(lines : Array(String), calls : Array(String), path : String,
                               root_url : String, endpoints : Hash(String, Endpoint))
      type_urls = mitchellh_cmd_type_urls(lines, root_url)
      mitchellh_cmd_keys(lines).each do |key, line_no|
        fetch_endpoint(endpoints, "#{root_url}/#{key}", path, line_no)
      end

      current_url : String? = nil
      lines.each_with_index do |line, index|
        line_no = index + 1

        if m = line.match(MITCHELLH_RUN_FUNC_RE)
          current_url = type_urls[m[1]]?
          next
        end
        if current_url && line.matches?(TOPLEVEL_BRACE_CLOSE_RE)
          current_url = nil
          next
        end
        next unless url = current_url

        call = calls[index]
        if m = call.match(MITCHELLH_FLAGVAR_RE)
          ep = fetch_endpoint(endpoints, url, path, line_no)
          ep.push_param(Param.new(m[1], "", "flag"))
        end
        call.scan(OS_GETENV_RE) do |env_match|
          ep = fetch_endpoint(endpoints, url, path, line_no)
          ep.push_param(Param.new(env_match[1], "", "env"))
        end
      end
    end
  end
end
