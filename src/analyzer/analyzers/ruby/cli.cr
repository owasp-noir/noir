require "../../../models/analyzer"
require "../../engines/ruby_engine"

module Analyzer::Ruby
  # Surfaces the command-line attack surface of Ruby programs as `cli://`
  # endpoints: one endpoint per (sub)command, with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers stdlib OptionParser / ARGV plus
  # Thor, GLI, Slop, TTY::Option and the commander gem.
  #
  # Line-scan analyzer (house style for non-tree-sitter Ruby adapters),
  # merging endpoints by URL across files.
  class Cli < RubyEngine
    # OptionParser: `opts.on("-p", "--port PORT")` — prefer the long name.
    OPTPARSE_LONG  = /\.on\s*\(?[^)]*?["'](-{2}[A-Za-z0-9][\w-]*)/
    OPTPARSE_SHORT = /\.on\s*\(\s*["'](-[A-Za-z0-9])(?:["' ]|\))/

    # Thor DSL.
    THOR_SUBCLASS = /<\s*Thor\b/
    THOR_DESC     = /^\s*desc\s+["']([^"'\s]+)/
    THOR_OPTION   = /^\s*(?:method_option|option)\s+:?["']?([A-Za-z0-9][\w-]*)/
    DEF_RE        = /^\s*def\s+([a-z_][\w]*[?!]?)/

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

    # Program-name hints.
    COMMANDER_PROGRAM = /\bprogram\s+:name\s*,\s*["']([^"']+)["']/
    OPTPARSE_BANNER   = /banner\s*=\s*["']Usage:\s*(\S+)/

    # Web frameworks: their ENV reads are config, not a CLI surface.
    WEB_FRAMEWORK_RE = /(?:^|\n)\s*require\s+["'](?:sinatra|rails|action_controller|active_record|grape|hanami|roda|rack|rackup|puma|unicorn|thin)\b|<\s*(?:Sinatra::Base|Grape::API|ApplicationController)\b|Rails\.application/

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
            emit_env = !content.matches?(WEB_FRAMEWORK_RE)

            scan(lines, path, root_url, endpoints, thor, emit_env)
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
        content.includes?("OptionParser.new") ||
        content.includes?("GLI::App") ||
        content.matches?(/\bSlop\.(?:parse|new)\b/) ||
        content.includes?("TTY::Option") ||
        content.includes?("Commander::Methods") ||
        content.matches?(ARGV_INDEX)
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
                     endpoints : Hash(String, Endpoint), thor : Bool, emit_env : Bool)
      pending_desc : String? = nil
      pending_thor_opts = [] of String
      block_cmd_url = root_url

      lines.each_with_index do |line, index|
        line_no = index + 1

        if thor
          if m = line.match(THOR_DESC)
            pending_desc = m[1]
          elsif m = line.match(THOR_OPTION)
            pending_thor_opts << m[1]
          elsif (m = line.match(DEF_RE)) && (name = m[1]) != "initialize"
            command = pending_desc || name
            url = "#{root_url}/#{command}"
            ep = fetch_endpoint(endpoints, url, path, line_no)
            pending_thor_opts.each { |opt| ep.push_param(Param.new(opt, "", "flag")) }
            pending_desc = nil
            pending_thor_opts.clear
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
