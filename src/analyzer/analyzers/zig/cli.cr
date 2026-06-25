require "../../../models/analyzer"

module Analyzer::Zig
  # Surfaces the command-line attack surface of Zig programs as `cli://`
  # endpoints: zig-clap param strings and zig-cli literals plus std.process
  # argv / env reads. Line-scan, merged by URL.
  class Cli < Analyzer
    # zig-clap multiline param string lines (each begins with `\\`).
    CLAP_FLAG = /\\\\\s*(?:-[A-Za-z0-9]\s*,\s*)?--([A-Za-z0-9][\w-]*)/
    CLAP_ARG  = /\\\\\s*<([A-Za-z_]\w*)>/
    # zig-cli struct literals. (Only flags are extracted: a `.name` literal is
    # ambiguous between the app name, a subcommand, and a positional-arg name,
    # so subcommand extraction from zig-cli is a follow-up.)
    CLI_LONG = /\.long_name\s*=\s*"(-{0,2}[A-Za-z0-9][\w-]*)"/
    # builtin.
    ARGS_IDX = /\bargs\s*\[\s*(\d+)\s*\]/
    GET_ENV  = /\b(?:std\.process\.getEnvVarOwned\s*\(\s*[\w.]+\s*,\s*"([^"]+)"|(?:std\.)?posix\.getenv\s*\(\s*"([^"]+)")/

    MARKERS = /@import\s*\(\s*"cli"\s*\)|@import\s*\(\s*"clap"\s*\)|\b(?:std\.)?process\.argsAlloc\s*\(|\bclap\.(?:parseParamsComptime|parse)\b|\bcli\.(?:Command|App|Runner)\b/
    WEB_RE  = /@import\s*\(\s*"(?:zap|jetzig|httpz|tokamak)"\s*\)/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".zig").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)
          binary = cli_binary_name(path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_RE)
          fetch_endpoint(endpoints, root_url, path, 1)
          content.each_line.with_index do |line, index|
            line_no = index + 1
            if m = line.match(CLAP_FLAG)
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
            elsif m = line.match(CLAP_ARG)
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].downcase, "", "argument"))
            end
            if m = line.match(CLI_LONG)
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
            end
            if m = line.match(ARGS_IDX)
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument")) unless m[1] == "0"
            end
            if emit_env
              line.scan(GET_ENV) do |em|
                name = em[1]? || em[2]?
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "env")) if name
              end
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

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".zig")
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      path.downcase.includes?("/test") || path.includes?("_test.")
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
