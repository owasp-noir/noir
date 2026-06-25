require "../../../models/analyzer"

module Analyzer::Clojure
  # Surfaces the command-line attack surface of Clojure programs as `cli://`
  # endpoints: clojure.tools.cli option specs, cli-matic config, and
  # *command-line-args* / (System/getenv). Line-scan, merged by URL.
  class Cli < Analyzer
    TOOLS_CLI_LONG = /"--([A-Za-z0-9][\w-]*)/
    TOOLS_CLI_SPEC = /\[\s*(?:(?:"-[A-Za-z0-9]"|nil)\s+)?"--/
    MATIC_COMMAND  = /:command\s+"([^"]+)"/
    MATIC_OPTION   = /:option\s+"([A-Za-z0-9][\w-]*)"/
    NTH_ARGS       = /\(\s*nth\s+(?:\*command-line-args\*|args)\s+(\d+)/
    GET_ENV        = /\(\s*System\/getenv\s+"([^"]+)"/

    MARKERS = /clojure\.tools\.cli\b|\(\s*(?:[\w.-]+\/)?parse-opts\b|\bcli-matic\b|\*command-line-args\*/
    WEB_RE  = /\b(?:compojure|ring\.adapter|reitit|io\.pedestal|httpkit|aleph)\b/

    def analyze
      endpoints = {} of String => Endpoint
      [".clj", ".cljs", ".cljc"].each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cli_test_path?(path)
          next unless File.exists?(path)
          begin
            content = read_file_content(path)
            next unless content.matches?(MARKERS)
            root_url = "cli://#{cli_binary_name(path)}"
            emit_env = !content.matches?(WEB_RE)
            current_url = root_url
            content.each_line.with_index do |line, index|
              line_no = index + 1
              if m = line.match(MATIC_COMMAND)
                current_url = "#{root_url}/#{m[1]}"
                fetch_endpoint(endpoints, current_url, path, line_no)
              end
              # tools.cli option vectors: ["-p" "--port PORT" ...]. `scan` so
              # several vectors on one line (and the long-only form) all surface.
              if line.matches?(TOOLS_CLI_SPEC)
                line.scan(TOOLS_CLI_LONG) { |lm| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(lm[1], "", "flag")) }
              end
              if m = line.match(MATIC_OPTION)
                fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(NTH_ARGS)
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
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, File.extname(path))
      if stem == "core" || stem == "main" || stem == "cli" || stem == "app"
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
