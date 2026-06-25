require "../../../models/analyzer"

module Analyzer::Dart
  # Surfaces the command-line attack surface of Dart programs as `cli://`
  # endpoints: the args package (ArgParser / CommandRunner) plus
  # main(List<String>) argv and Platform.environment. Line-scan, merged by URL.
  class Cli < Analyzer
    ARGPARSER_VAR  = /(\w+)\s*=\s*ArgParser\s*\(/
    SUBCOMMAND_VAR = /(\w+)\s*=\s*\w+\s*\.\s*addCommand\s*\(\s*['"]([^'"]+)['"]/
    ADD_COMMAND    = /\.addCommand\s*\(\s*['"]([^'"]+)['"]/
    ADD_OPTION     = /(\w+)\s*\.\s*addOption\s*\(\s*['"]([^'"]+)['"]/
    ADD_FLAG       = /(\w+)\s*\.\s*addFlag\s*\(\s*['"]([^'"]+)['"]/
    RUNNER_NAME    = /\bget\s+name\s*=>\s*['"]([^'"]+)['"]/
    ARGS_IDX       = /\bargs\s*\[\s*(\d+)\s*\]/
    PLATFORM_ENV   = /Platform\.environment\s*\[\s*['"]([^'"]+)['"]\s*\]/

    MARKERS = /package:args\/|package:dcli\/|\bArgParser\s*\(|\bCommandRunner\b|\bextends\s+Command\b|main\s*\(\s*List<String>/
    WEB_RE  = /package:shelf\/|package:dart_frog|package:angel3|package:alfred|\bHttpServer\.bind\b/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".dart").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)
          root_url = "cli://#{cli_binary_name(path)}"
          emit_env = !content.matches?(WEB_RE)
          scan(content.lines, path, root_url, endpoints, emit_env)
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def scan(lines, path, root_url, endpoints, emit_env)
      current_url = root_url            # cursor for CommandRunner `get name`
      var_urls = {} of String => String # ArgParser / addCommand variables
      lines.each_with_index do |line, index|
        line_no = index + 1

        if m = line.match(ARGPARSER_VAR)
          var_urls[m[1]] = root_url
        end
        if m = line.match(SUBCOMMAND_VAR)
          url = "#{root_url}/#{m[2]}"
          var_urls[m[1]] = url
          current_url = url
          fetch_endpoint(endpoints, url, path, line_no)
        elsif m = line.match(ADD_COMMAND)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end
        if m = line.match(RUNNER_NAME)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end
        # Options/flags attribute by receiver variable (root parser vs a
        # subcommand var); CommandRunner's `argParser.addOption` falls back to
        # the current `get name` cursor.
        if m = line.match(ADD_OPTION)
          fetch_endpoint(endpoints, var_urls[m[1]]? || current_url, path, line_no).push_param(Param.new(m[2], "", "flag"))
        end
        if m = line.match(ADD_FLAG)
          fetch_endpoint(endpoints, var_urls[m[1]]? || current_url, path, line_no).push_param(Param.new(m[2], "", "flag"))
        end
        if m = line.match(ARGS_IDX)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
        end
        if emit_env
          line.scan(PLATFORM_ENV) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
        end
      end
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".dart")
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("_test.")
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
