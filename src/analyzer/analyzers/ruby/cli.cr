require "../../../models/analyzer"
require "../../engines/ruby_engine"

module Analyzer::Ruby
  # Surfaces the command-line attack surface of Ruby programs as `cli://`
  # endpoints: one endpoint per (sub)command, with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers stdlib OptionParser / ARGV plus
  # Thor, GLI, Slop, TTY::Option, the commander gem, Optimist, Clamp and
  # dry-cli.
  #
  # Line-scan analyzer (house style for non-tree-sitter Ruby adapters),
  # merging endpoints by URL across files.
  class Cli < RubyEngine
    # OptionParser: `opts.on("-p", "--port PORT")` — prefer the long name.
    OPTPARSE_LONG  = /\.on\s*\(?[^)]*?["'](-{2}[A-Za-z0-9][\w-]*)/
    OPTPARSE_SHORT = /\.on\s*\(\s*["'](-[A-Za-z0-9])(["' ]|\))/

    # Thor DSL.
    THOR_SUBCLASS = /<\s*Thor\b/
    THOR_DESC     = /^\s*desc\s+["']([^"'\s]+)/
    THOR_OPTION   = /^\s*(?:method_option|option)\s+:?["']?([A-Za-z0-9][\w-]*)/
    # Instance methods only: `def self.exit_on_failure?` (standard Thor
    # boilerplate) is a class method, never a command, so the name must be
    # followed by an argument list, whitespace or end-of-line — not `.`.
    DEF_RE = /^\s*def\s+([a-z_]\w*[?!]?)\s*(?:[(\s]|$)/

    # GLI / commander gem command blocks + flags.
    BLOCK_COMMAND = /^\s*command\s+:?["']?([A-Za-z0-9][\w-]*)/
    GLI_FLAG      = /^\s*(?:flag|switch)\s+:?["']?([A-Za-z0-9][\w-]*)/
    COMMANDER_OPT = /\bc\.option\s+[^\n]*?["'](-{2}[A-Za-z0-9][\w-]*)/

    # Slop: `o.string '-p', '--port'`.
    SLOP_LONG = /\bo\.(?:string|integer|int|float|bool|boolean|array|symbol|null|on)\s+[^\n]*?["'](-{2}[A-Za-z0-9][\w-]*)/

    # TTY::Option DSL (only when no Thor class is present, to avoid clashing
    # with Thor's `option`).
    TTY_OPTION_DECL   = /^\s*(?:option|flag|keyword)\s+:?(\w+)/
    TTY_ARGUMENT_DECL = /^\s*argument\s+:?(\w+)/

    # builtin argv / env.
    ARGV_INDEX = /\bARGV\s*\[\s*(\d+)\s*\]/
    ENV_INDEX  = /\bENV\s*\[\s*["']([^"']+)["']\s*\]/
    ENV_FETCH  = /\bENV\.fetch\s*\(\s*["']([^"']+)["']/

    # Optimist: `opt :name, "desc", type: :string` — a flat parser (no
    # subcommand DSL), gated on the block-opening call so a bare local
    # variable/method named `opt` elsewhere doesn't false-positive.
    OPTIMIST_CALL = /\bOptimist(?:::|\.)options\b/
    OPTIMIST_OPT  = /^\s*opt\s+:([A-Za-z0-9_]+)/

    # Clamp: `class Foo < Clamp::Command` with `option`/`parameter` DSL and
    # optional nested `subcommand "name", "desc" do ... end` blocks. The DSL
    # call's first argument (the switch name or an array of switch names)
    # must appear immediately after `option` + whitespace — a `(?=["'\[])`
    # lookahead — so an unrelated local/instance variable assignment like
    # `option = default? ? "--json" : "--text"` cannot masquerade as the
    # DSL call just because a dash-prefixed quoted string appears somewhere
    # later on the line. Mirrors CLAMP_PARAMETER, which already requires the
    # quote directly after the keyword.
    CLAMP_SUBCLASS     = /<\s*Clamp::Command\b/
    CLAMP_SUBCOMMAND   = /^(\s*)subcommand\s+["']([A-Za-z0-9][\w-]*)["'][^\n]*\bdo\s*$/
    CLAMP_OPTION_LONG  = /^\s*option\s+(?=["'\[])[^\n]*?["'](-{2}[A-Za-z0-9][\w-]*)["']/
    CLAMP_OPTION_SHORT = /^\s*option\s+(?=["'\[])[^\n]*?["'](-[A-Za-z0-9])["']/
    CLAMP_PARAMETER    = /^\s*parameter\s+["']\[?([A-Za-z0-9_]+)/

    # dry-cli: `class Build < Dry::CLI::Command` with `option`/`argument`
    # DSL; each subclass is its own (sub)command. DRY_CLI_MARKER (unanchored)
    # is for whole-content evidence checks; DRY_CLI_CLASS (line-anchored, to
    # capture indent) is for the per-line scan — `^` in Crystal only matches
    # the very start of a multi-line string, not after every `\n`.
    DRY_CLI_MARKER   = /<\s*Dry::CLI::Command\b/
    DRY_CLI_CLASS    = /^(\s*)class\s+([A-Za-z0-9_]+)\s*<\s*Dry::CLI::Command\b/
    DRY_CLI_OPTION   = /^\s*option\s+:([A-Za-z0-9_]+)/
    DRY_CLI_ARGUMENT = /^\s*argument\s+:([A-Za-z0-9_]+)/

    # Program-name hints.
    COMMANDER_PROGRAM = /\bprogram\s+:name\s*,\s*["']([^"']+)["']/
    OPTPARSE_BANNER   = /banner\s*=\s*["']Usage:\s*(\S+)/

    # Web frameworks: their ENV reads are config, not a CLI surface.
    WEB_FRAMEWORK_RE = /(?:^|\n)\s*require\s+["'](?:sinatra|rails|action_controller|active_record|grape|hanami|roda|rack|rackup|puma|unicorn|thin)\b|<\s*(?:Sinatra::Base|Grape::API|ApplicationController)\b|Rails\.application/

    # `cli_evidence?` runs once per .rb file and OR-ed four String#includes?
    # scans as a standalone boolean gate. Folded into one precompiled union
    # so the literal-marker half of the gate costs a single PCRE2 match
    # instead of up to four naive substring scans.
    CLI_EVIDENCE_MARKERS_RE = Regex.union("OptionParser.new", "GLI::App", "TTY::Option", "Commander::Methods")

    def analyze
      endpoints = {} of String => Endpoint

      base_paths.each do |current_base_path|
        get_files_by_extension(".rb").each do |path|
          next unless path_under_root?(path, current_base_path)
          next if RubyEngine.ruby_test_path?(path)

          begin
            content = read_file_content(path)
            next unless cli_evidence?(content)

            binary = ruby_binary_name(content, path)
            root_url = "cli://#{binary}"
            lines = content.lines
            thor = content.matches?(THOR_SUBCLASS)
            clamp = content.matches?(CLAMP_SUBCLASS)
            dry_cli = content.matches?(DRY_CLI_MARKER)
            optimist = content.matches?(OPTIMIST_CALL)
            emit_env = !content.matches?(WEB_FRAMEWORK_RE)

            scan(lines, path, root_url, endpoints, thor, emit_env, clamp, dry_cli, optimist)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end

      endpoints.each_value { |ep| @result << ep }
      Fiber.yield
      @result
    end

    private def cli_evidence?(content : String) : Bool
      content.matches?(THOR_SUBCLASS) ||
        content.matches?(CLI_EVIDENCE_MARKERS_RE) ||
        content.matches?(/\bSlop\.(?:parse|new)\b/) ||
        content.matches?(ARGV_INDEX) ||
        content.matches?(OPTIMIST_CALL) ||
        content.matches?(CLAMP_SUBCLASS) ||
        content.matches?(DRY_CLI_MARKER)
    end

    private def ruby_binary_name(content : String, path : String) : String
      if m = content.match(COMMANDER_PROGRAM)
        return m[1]
      end
      if m = content.match(OPTPARSE_BANNER)
        return m[1]
      end
      stem = File.basename(path, ".rb")
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def scan(lines : Array(String), path : String, root_url : String,
                     endpoints : Hash(String, Endpoint), thor : Bool, emit_env : Bool,
                     clamp : Bool, dry_cli : Bool, optimist : Bool)
      pending_desc : String? = nil
      pending_thor_opts = [] of String
      block_cmd_url = root_url
      thor_private = false
      no_commands_indent : Int32? = nil
      clamp_sub_indent : Int32? = nil
      clamp_sub_url = root_url
      dry_cli_indent : Int32? = nil
      dry_cli_url : String? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        # NOTE: `thor`/`clamp`/`dry_cli`/`optimist` are mutually exclusive
        # branches — intentionally one-DSL-per-file, matching the existing
        # TTY::Option-vs-Thor precedent above. A file that (unusually) mixes
        # markers for two of these frameworks only has the first-checked
        # framework's option/argument declarations scanned; the other
        # framework's class still gets a root/command endpoint (via
        # `cli_evidence?`/`DEF_RE`/etc. where applicable) but its
        # `option`/`parameter`/`argument` lines are silently skipped rather
        # than merged. This is a deliberate simplification: real-world Ruby
        # CLI files essentially never combine two CLI DSLs in one file, and
        # per-line (rather than per-file) dispatch would require detecting
        # which framework's *block* a given line sits in, which the
        # line-scan house style doesn't support today.
        if thor
          # Thor's task rules: `no_commands do ... end` bodies and methods
          # below a bare `private` are helpers, not commands. Track both so
          # they don't surface as bogus subcommands (an indentation-matched
          # `end` is the line-scan approximation of the block boundary).
          # Only the `do ... end` form arms the tracker: a single-line
          # `no_commands { ... }` closes on its own line, so treating it as
          # an open block would suppress every later command in the file.
          if nc = line.match(/^(\s*)no_commands\s+do\b/)
            no_commands_indent ||= nc[1].size
          elsif (indent = no_commands_indent) && (em = line.match(/^(\s*)end\b/)) && em[1].size <= indent
            no_commands_indent = nil
          end
          if line.matches?(/^\s*private\s*$/)
            thor_private = true
          elsif line.matches?(/^\s*public\s*$/) || line.matches?(THOR_SUBCLASS)
            thor_private = false
          end

          if m = line.match(THOR_DESC)
            pending_desc = m[1]
          elsif m = line.match(THOR_OPTION)
            pending_thor_opts << m[1]
          elsif (m = line.match(DEF_RE)) && (name = m[1]) != "initialize"
            if thor_private || no_commands_indent
              pending_desc = nil
              pending_thor_opts.clear
            else
              command = pending_desc || name
              url = "#{root_url}/#{command}"
              ep = fetch_endpoint(endpoints, url, path, line_no)
              pending_thor_opts.each { |opt| ep.push_param(Param.new(opt, "", "flag")) }
              pending_desc = nil
              pending_thor_opts.clear
            end
          end
        elsif clamp
          # Clamp: `option`/`parameter` attach to the innermost open
          # `subcommand "name" do ... end` block (indent-scoped, never a
          # sticky cursor), falling back to the root command.
          if sc = line.match(CLAMP_SUBCOMMAND)
            clamp_sub_indent = sc[1].size
            clamp_sub_url = "#{root_url}/#{sc[2]}"
            fetch_endpoint(endpoints, clamp_sub_url, path, line_no)
          elsif (indent = clamp_sub_indent) && (em = line.match(/^(\s*)end\b/)) && em[1].size <= indent
            clamp_sub_indent = nil
            clamp_sub_url = root_url
          end

          if m = line.match(CLAMP_OPTION_LONG)
            fetch_endpoint(endpoints, clamp_sub_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
          elsif m = line.match(CLAMP_OPTION_SHORT)
            fetch_endpoint(endpoints, clamp_sub_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
          end
          if m = line.match(CLAMP_PARAMETER)
            fetch_endpoint(endpoints, clamp_sub_url, path, line_no).push_param(Param.new(m[1].downcase, "", "argument"))
          end
        elsif dry_cli
          # dry-cli: each `class Xxx < Dry::CLI::Command` is its own
          # (sub)command; `option`/`argument` attach to the innermost open
          # class body (indent-scoped), never a sticky cursor.
          if cm = line.match(DRY_CLI_CLASS)
            dry_cli_indent = cm[1].size
            new_command_url = "#{root_url}/#{cm[2].downcase}"
            dry_cli_url = new_command_url
            fetch_endpoint(endpoints, new_command_url, path, line_no)
          elsif (indent = dry_cli_indent) && (em = line.match(/^(\s*)end\b/)) && em[1].size <= indent
            dry_cli_indent = nil
            dry_cli_url = nil
          end

          if url = dry_cli_url
            if m = line.match(DRY_CLI_OPTION)
              fetch_endpoint(endpoints, url, path, line_no).push_param(Param.new(m[1], "", "flag"))
            elsif m = line.match(DRY_CLI_ARGUMENT)
              fetch_endpoint(endpoints, url, path, line_no).push_param(Param.new(m[1], "", "argument"))
            end
          end
        elsif optimist
          # Optimist has no subcommand DSL: every `opt` declaration is a
          # flat, root-level flag.
          if m = line.match(OPTIMIST_OPT)
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
          end
        else
          # TTY::Option DSL (option/flag/keyword/argument) — only outside a
          # Thor class so it doesn't clash with Thor's `option`.
          if m = line.match(TTY_ARGUMENT_DECL)
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
          elsif m = line.match(TTY_OPTION_DECL)
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
          end
        end

        # GLI / commander command blocks (subcommands).
        if m = line.match(BLOCK_COMMAND)
          block_cmd_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, block_cmd_url, path, line_no)
        end
        if m = line.match(GLI_FLAG)
          fetch_endpoint(endpoints, block_cmd_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(COMMANDER_OPT)
          fetch_endpoint(endpoints, block_cmd_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        end

        # OptionParser + Slop options -> root.
        if m = line.match(OPTPARSE_LONG)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        elsif m = line.match(OPTPARSE_SHORT)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        end
        if m = line.match(SLOP_LONG)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        end

        # builtin argv positionals (ARGV excludes the program name, so ARGV[0]
        # is a real input argument).
        if m = line.match(ARGV_INDEX)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
        end

        # env reads -> root (gated to non-web files).
        if emit_env
          line.scan(ENV_INDEX) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
          line.scan(ENV_FETCH) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end
      end
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
