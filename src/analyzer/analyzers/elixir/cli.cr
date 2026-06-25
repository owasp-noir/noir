require "../../../models/analyzer"

module Analyzer::Elixir
  # Surfaces the command-line attack surface of Elixir programs as `cli://`
  # endpoints: stdlib OptionParser (switches), System.argv and System.get_env.
  # Line-scan; one root endpoint per binary (stdlib OptionParser has no
  # subcommands), params flag/argument/env, merged by URL.
  class Cli < Analyzer
    SWITCHES   = /switches:\s*\[([^\]]*)\]/
    SWITCH_KEY = /([a-z_]\w*):/
    ARGV       = /\bSystem\.argv\b/
    GET_ENV    = /\bSystem\.(?:get_env|fetch_env!?)\s*\(\s*"([^"]+)"/

    MARKERS = /\bOptionParser\.(?:parse|parse!|next)\b|\bSystem\.argv\b|\bOptimus\.new!?\b/
    WEB_RE  = /\buse\s+(?:Phoenix|Plug)\b|\bimport\s+Plug\b|\bBandit\b/

    def analyze
      endpoints = {} of String => Endpoint
      [".ex", ".exs"].each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cli_test_path?(path)
          next unless File.exists?(path)
          begin
            content = read_file_content(path)
            next unless content.matches?(MARKERS)
            root_url = "cli://#{cli_binary_name(path)}"
            emit_env = !content.matches?(WEB_RE)

            # Every `switches: [...]` keyword list (a file may dispatch several
            # OptionParser.parse calls). Endpoint is created lazily so a bare
            # `System.argv` file with no switches/env emits nothing.
            content.scan(SWITCHES) do |m|
              m[1].scan(SWITCH_KEY) { |sm| fetch_endpoint(endpoints, root_url, path, 1).push_param(Param.new(sm[1], "", "flag")) }
            end

            content.each_line.with_index do |line, index|
              if emit_env
                line.scan(GET_ENV) { |em| fetch_endpoint(endpoints, root_url, path, index + 1).push_param(Param.new(em[1], "", "env")) }
              end
            end
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, File.extname(path))
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
