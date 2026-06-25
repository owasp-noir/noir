require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  # Surfaces the command-line attack surface of C# programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers `Main(string[] args)` /
  # GetCommandLineArgs / GetEnvironmentVariable plus System.CommandLine,
  # CommandLineParser, CliFx and Spectre.Console.Cli.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. Subclasses Analyzer directly (there is no C# engine) and reuses
  # Common.csharp_test_path? to skip test files.
  class Cli < Analyzer
    include Common

    # System.CommandLine (builder).
    ROOT_COMMAND = /\bnew\s+RootCommand\b/
    NEW_COMMAND  = /\bnew\s+Command\s*\(\s*@?"([^"]+)"/
    NEW_OPTION   = /\bnew\s+Option(?:<[^>]*>)?\s*\(\s*@?"([^"]+)"/
    NEW_ARGUMENT = /\bnew\s+Argument(?:<[^>]*>)?\s*\(\s*@?"([^"]+)"/

    # Attribute-driven libs (CommandLineParser / CliFx / Spectre / airline-ish).
    VERB_ATTR   = /\[\s*(?:Verb|Command)\s*\(\s*@?"([^"]+)"/
    ADD_COMMAND = /\.AddCommand(?:<[^>]+>)?\s*\(\s*@?"([^"]+)"/
    OPTION_ATTR = /\[\s*(?:Option|CommandOption)\s*\(([^\]]*)\)/
    PARAM_ATTR  = /\[\s*CommandParameter\s*\(([^\]]*)\)/

    # builtin.
    GET_ENV      = /\bEnvironment\.GetEnvironmentVariable\s*\(\s*@?"([^"]+)"/
    MAIN_ARGS    = /\bstatic\s+(?:async\s+)?(?:int|void|Task(?:<int>)?)\s+Main\s*\(\s*string\s*\[\s*\]\s+(\w+)\s*\)/
    GET_CMD_ARGS = /\bEnvironment\.GetCommandLineArgs\s*\(/

    CLI_LIB_MARKERS = ["System.CommandLine", "CommandLine", "CliFx", "Spectre.Console.Cli"]
    WEB_HOST_RE     = /\bWebApplication\.(?:Create(?:Builder|SlimBuilder|EmptyBuilder)?|CreateDefault)\b|\bnew\s+HttpListener\b|\.MapGet\s*\(|\.MapControllers\s*\(|\[\s*ApiController\s*\]|:\s*ControllerBase\b|\bHost\.CreateDefaultBuilder\b/

    def analyze
      assemblies = collect_csproj_names
      endpoints = {} of String => Endpoint

      get_files_by_extension(".cs").each do |path|
        next if File.directory?(path)
        next if Common.csharp_test_path?(path)
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          next unless cli_evidence?(content)

          binary = csharp_binary_name(assemblies, path)
          root_url = "cli://#{binary}"
          framework_cli = CLI_LIB_MARKERS.any? { |m| content.includes?(m) }
          emit_builtin = framework_cli || !content.matches?(WEB_HOST_RE)
          scan(content.lines, path, binary, root_url, endpoints, emit_builtin)
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_evidence?(content : String) : Bool
      return true if CLI_LIB_MARKERS.any? { |m| content.includes?(m) }
      return true if content.matches?(ROOT_COMMAND) || content.matches?(VERB_ATTR)
      return false if content.matches?(WEB_HOST_RE)
      content.matches?(MAIN_ARGS) || content.matches?(GET_CMD_ARGS)
    end

    private def csharp_binary_name(assemblies : Array(Tuple(String, String)), path : String) : String
      expanded = File.expand_path(File.dirname(path))
      assemblies.each do |name, dir|
        return name if expanded == dir || expanded.starts_with?("#{dir}/")
      end
      stem = File.basename(path, ".cs")
      if stem == "Program" || stem == "Main" || stem == "Cli" || stem == "App"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def scan(lines : Array(String), path : String, binary : String,
                     root_url : String, endpoints : Hash(String, Endpoint), emit_builtin : Bool)
      current_url = root_url
      main_argv : String? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        main_argv = line.match(MAIN_ARGS).try(&.[1]) || main_argv

        # System.CommandLine builder: RootCommand -> root, new Command -> sub.
        current_url = root_url if line.matches?(ROOT_COMMAND)
        if m = line.match(NEW_COMMAND)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end
        if m = line.match(ADD_COMMAND)
          sub = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, sub, path, line_no)
          current_url = sub
        end
        if m = line.match(NEW_OPTION)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        end
        if m = line.match(NEW_ARGUMENT)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "argument"))
        end

        # Attribute-driven libs: [Verb/Command("x")] opens a subcommand whose
        # following [Option]/[Value]/[CommandParameter] properties bind to it.
        if m = line.match(VERB_ATTR)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end
        if m = line.match(OPTION_ATTR)
          if name = attr_option_name(m[1])
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(name, "", "flag"))
          end
        end
        if m = line.match(PARAM_ATTR)
          # Spectre [CommandArgument(0, "<name>")] -> argument by label.
          if lbl = m[1].match(/[<\[]([A-Za-z0-9_-]+)[>\]]/)
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(lbl[1], "", "argument"))
          end
        end

        # builtin argv positional + env (gated).
        if emit_builtin
          if (argv = main_argv) && (m = line.match(/\b#{Regex.escape(argv)}\s*\[\s*(\d+)\s*\]/))
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
          end
          line.scan(GET_ENV) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end
      end
    end

    # Extracts the flag name from a [Option(...)] / [CommandOption(...)] body.
    # CommandLineParser uses ('x', "name") or ("name"); CliFx ("name");
    # Spectre ("-n|--name"). Prefer the long form.
    private def attr_option_name(body : String) : String?
      tokens = [] of String
      body.scan(/["']([^"']+)["']/) { |m| tokens << m[1] }
      return if tokens.empty?
      # Spectre packs "-n|--name" into one token.
      long = nil
      short = nil
      tokens.each do |tok|
        tok.split('|').each do |part|
          part = part.strip
          if part.starts_with?("--")
            long ||= part.lstrip('-')
          elsif part.starts_with?("-")
            short ||= part.lstrip('-')
          else
            long ||= part
          end
        end
      end
      long || short
    end

    private def collect_csproj_names : Array(Tuple(String, String))
      out = [] of Tuple(String, String)
      get_files_by_extension(".csproj").each do |path|
        begin
          content = read_file_content(path)
        rescue
          next
        end
        name = content.match(/<AssemblyName>\s*([^<\s]+)\s*<\/AssemblyName>/).try(&.[1]) ||
               File.basename(path, ".csproj")
        out << {name, File.expand_path(File.dirname(path))}
      end
      out.sort_by! { |(_n, dir)| -dir.size }
      out
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
