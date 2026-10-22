require "../../../models/analyzer"
require "../../engines/cli_endpoint_support"

module Analyzer::Elixir
  # Surfaces the command-line attack surface of Elixir programs as `cli://`
  # endpoints: stdlib OptionParser (switches), System.argv and System.get_env.
  # Line-scan; one root endpoint per binary (stdlib OptionParser has no
  # subcommands), params flag/argument/env, merged by URL.
  class Cli < Analyzer
    analyzer_for "elixir_cli"

    include CliEndpointSupport

    SWITCHES   = /switches:\s*\[([^\]]*)\]/
    SWITCH_KEY = /([a-z_]\w*):/
    GET_ENV    = /\bSystem\.(?:get_env|fetch_env!?)\s*\(\s*"([^"]+)"/

    MARKERS = /\bOptionParser\.(?:parse|parse!|next)\b|\bSystem\.argv\b|\bOptimus\.new!?\b/
    WEB_RE  = /\buse\s+(?:Phoenix|Plug)\b|\bimport\s+Plug\b|\bBandit\b/

    def analyze
      endpoints = {} of String => Endpoint
      files = get_files_by_extension(".ex") + get_files_by_extension(".exs")

      files.each do |path|
        next if cli_test_path?(path)
        begin
          content = read_file_content(path)
          # Cheap reject before the full MARKERS regex: every alternative
          # contains one of these literals.
          next unless content.includes?("OptionParser") ||
                      content.includes?("System.argv") ||
                      content.includes?("Optimus")
          next unless content.matches?(MARKERS)

          root_url = "cli://#{cli_binary_name(path)}"
          emit_env = !content.matches?(WEB_RE)

          # Every `switches: [...]` keyword list (a file may dispatch several
          # OptionParser.parse calls). Endpoint is created lazily so a bare
          # `System.argv` file with no switches/env emits nothing.
          if content.includes?("switches:")
            content.scan(SWITCHES) do |m|
              m[1].scan(SWITCH_KEY) { |sm| fetch_endpoint(endpoints, root_url, path, 1).push_param(Param.new(sm[1], "", "flag")) }
            end
          end

          # Env extraction is the only per-line work; skip the line walk
          # entirely for web modules or files with no System env reads.
          if emit_env && (content.includes?("get_env") || content.includes?("fetch_env"))
            content.each_line.with_index do |line, index|
              next unless line.includes?("get_env") || line.includes?("fetch_env")
              line.scan(GET_ENV) { |em| fetch_endpoint(endpoints, root_url, path, index + 1).push_param(Param.new(em[1], "", "env")) }
            end
          end
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end
      @result.concat(cli_endpoints(endpoints))
      @result
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, File.extname(path))
      if stem == "main" || stem == "cli" || stem == "app"
        if name = cli_directory_binary_name(path)
          return name
        end
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      # Scan-base-relative, never absolute: a `test/` directory ABOVE the
      # scan base is not this project's test tree.
      lower = base_relative_path(path).downcase
      lower.includes?("/test/") || lower.includes?("_test.")
    end
  end
end
