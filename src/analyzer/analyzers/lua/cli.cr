require "../../../models/analyzer"

module Analyzer::Lua
  # Surfaces the command-line attack surface of Lua programs as `cli://`
  # endpoints: the argparse library (option/flag/argument/command, attributed
  # by receiver variable) plus `arg` indexing and os.getenv. Line-scan,
  # merged by URL.
  class Cli < Analyzer
    ARGPARSE_CTOR = /(?:local\s+)?([A-Za-z_]\w*)\s*=\s*argparse\s*\(\s*(?:['"]([^'"]*)['"])?/
    SUBCOMMAND    = /(?:local\s+)?(?:([A-Za-z_]\w*)\s*=\s*)?([A-Za-z_]\w*)\s*:\s*command\s*\(\s*['"]([^'"]+)['"]/
    OPTION        = /([A-Za-z_]\w*)\s*:\s*(?:option|flag)\s*\(\s*['"]([^'"]+)['"]/
    ARGUMENT      = /([A-Za-z_]\w*)\s*:\s*argument\s*\(\s*['"]([^'"]+)['"]/
    ARG_IDX       = /\barg\s*\[\s*(\d+)\s*\]/
    GET_ENV       = /\bos\.getenv\s*\(\s*['"]([^'"]+)['"]/

    MARKERS = /\brequire\s*\(?\s*['"]argparse['"]|\bargparse\s*\(|\barg\s*\[\s*\d+\s*\]/
    WEB_RE  = /\brequire\s*\(?\s*['"](?:lapis|lor)['"]/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".lua").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)
          # binary: argparse("name") if present, else file stem.
          name_match = content.match(/argparse\s*\(\s*['"]([^'"]+)['"]/)
          binary = name_match ? name_match[1] : cli_binary_name(path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_RE)
          var_urls = {} of String => String

          content.each_line.with_index do |line, index|
            line_no = index + 1
            if m = line.match(ARGPARSE_CTOR)
              var_urls[m[1]] = root_url
            end
            if m = line.match(SUBCOMMAND)
              url = "#{root_url}/#{m[3]}"
              var_urls[m[1]] = url if m[1]?
              fetch_endpoint(endpoints, url, path, line_no)
            end
            if m = line.match(OPTION)
              fetch_endpoint(endpoints, var_urls[m[1]]? || root_url, path, line_no).push_param(Param.new(opt_long(m[2]), "", "flag"))
            end
            if m = line.match(ARGUMENT)
              fetch_endpoint(endpoints, var_urls[m[1]]? || root_url, path, line_no).push_param(Param.new(m[2], "", "argument"))
            end
            if m = line.match(ARG_IDX)
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
            end
            if emit_env
              line.scan(GET_ENV) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
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

    # argparse alias spec ("-p --port" / "--port") -> long name without dashes.
    private def opt_long(raw : String) : String
      tokens = raw.split(/\s+/)
      long = tokens.find(&.starts_with?("--")) || tokens.find(&.starts_with?("-")) || tokens.first?
      (long || raw).lstrip('-')
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".lua")
      if stem == "main" || stem == "cli" || stem == "init"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("_spec.") || lower.includes?("/test/")
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
