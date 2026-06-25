require "../../../models/analyzer"
require "../../engines/php_engine"

module Analyzer::Php
  # Surfaces the command-line attack surface of PHP programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers Symfony Console plus builtin
  # getopt / $argv / $_ENV / getenv.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. Subclasses Analyzer directly (PhpEngine is abstract) and reuses
  # PhpEngine.test_path? to skip tests.
  class Cli < Analyzer
    SET_NAME     = /\$this->setName\s*\(\s*['"]([^'"]+)['"]/
    DEFAULT_NAME = /protected\s+(?:static\s+)?\$defaultName\s*=\s*['"]([^'"]+)['"]/
    AS_COMMAND   = /#\[\s*AsCommand\s*\(\s*name\s*:\s*['"]([^'"]+)['"]/
    ADD_ARGUMENT = /->\s*addArgument\s*\(\s*['"]([^'"]+)['"]/
    ADD_OPTION   = /->\s*addOption\s*\(\s*['"]([^'"]+)['"]/
    GET_OPTION   = /\$input->getOption\s*\(\s*['"]([^'"]+)['"]/
    GET_ARGUMENT = /\$input->getArgument\s*\(\s*['"]([^'"]+)['"]/

    GETOPT      = /\bgetopt\s*\(\s*(['"])([^'"]*)\1\s*(?:,\s*\[([^\]]*)\])?/
    ARGV_INDEX  = /\$argv\s*\[\s*(\d+)\s*\]/
    ENV_BRACKET = /\$_ENV\s*\[\s*['"]([^'"]+)['"]\s*\]/
    GETENV      = /\bgetenv\s*\(\s*['"]([^'"]+)['"]/

    WEB_FRAMEWORK_RE = /\buse\s+(?:Illuminate\\(?:Foundation|Http|Routing)|Symfony\\Bundle\\FrameworkBundle|Symfony\\Component\\HttpFoundation|Symfony\\Component\\HttpKernel|Slim\\(?:App|Factory)|Laminas\\(?:Mvc|Mezzio)|Mezzio\\|Cake\\(?:Routing|Http)|Hyperf\\HttpServer)\b|extends\s+AbstractController\b/

    def analyze
      endpoints = {} of String => Endpoint

      get_files_by_extension(".php").each do |path|
        next if File.directory?(path)
        next if PhpEngine.test_path?(path)
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          next unless cli_evidence?(content)

          binary = php_binary_name(path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_FRAMEWORK_RE)
          scan(content.lines, path, root_url, endpoints, emit_env)
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_evidence?(content : String) : Bool
      content.includes?("Symfony\\Component\\Console") || content.matches?(/\bextends\s+Command\b/) ||
        content.matches?(AS_COMMAND) || content.matches?(GETOPT) || content.matches?(ARGV_INDEX) ||
        content.includes?("League\\CLImate") || content.includes?("Minicli\\")
    end

    private def php_binary_name(path : String) : String
      base = @base_path.empty? ? File.dirname(path) : @base_path
      name = File.basename(File.expand_path(base))
      name.empty? ? File.basename(path, ".php") : name
    end

    private def scan(lines : Array(String), path : String, root_url : String,
                     endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url

      lines.each_with_index do |line, index|
        line_no = index + 1

        # Symfony command name (setName / $defaultName / #[AsCommand]).
        if m = line.match(SET_NAME) || line.match(DEFAULT_NAME) || line.match(AS_COMMAND)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end

        if m = line.match(ADD_OPTION) || line.match(GET_OPTION)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(ADD_ARGUMENT) || line.match(GET_ARGUMENT)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end

        # builtin getopt: short spec + optional long-opt array (root flags).
        if m = line.match(GETOPT)
          parse_getopt_short(m[2], fetch_endpoint(endpoints, root_url, path, line_no))
          if longs = m[3]?
            longs.scan(/['"]([^'"]+)['"]/) do |lm|
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(lm[1].rstrip(':'), "", "flag"))
            end
          end
        end

        if m = line.match(ARGV_INDEX)
          # $argv[0] is the script name, not input.
          unless m[1] == "0"
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
          end
        end

        if emit_env
          line.scan(ENV_BRACKET) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
          line.scan(GETENV) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
        end
      end
    end

    private def parse_getopt_short(spec : String, endpoint : Endpoint)
      spec.each_char do |ch|
        next if ch == ':'
        endpoint.push_param(Param.new(ch.to_s, "", "flag"))
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
