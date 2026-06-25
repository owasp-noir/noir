require "../../../models/analyzer"

module Analyzer::Scala
  # Surfaces the command-line attack surface of Scala programs as `cli://`
  # endpoints: scopt and decline (options/args/subcommands) plus sys.env
  # reads. Line-scan, merged by URL.
  class Cli < Analyzer
    SCOPT_OPT = /\bopt\[[^\]]*\]\s*\(\s*(?:'[A-Za-z0-9]'\s*,\s*)?"([^"]+)"/
    SCOPT_ARG = /\barg\[[^\]]*\]\s*\(\s*"<?([A-Za-z0-9][\w-]*)>?"/
    SCOPT_CMD = /\bcmd\s*\(\s*"([^"]+)"/
    DEC_OPT   = /\bOpts\.option\[[^\]]*\]\s*\(\s*"([^"]+)"/
    DEC_FLAG  = /\bOpts\.flag\s*\(\s*"([^"]+)"/
    DEC_ARG   = /\bOpts\.argument(?:\[[^\]]*\])?\s*\(\s*"<?([A-Za-z0-9][\w-]*)>?"/
    DEC_CMD   = /\bCommand\s*\(\s*"([^"]+)"/
    SYS_ENV   = /\bsys\.env\s*(?:\(\s*"([^"]+)"|\.get\s*\(\s*"([^"]+)")/

    MARKERS = /\bscopt\b|\bOParser\b|\bcom\.monovore\.decline\b|\bOpts\.(?:option|flag|argument|arguments)\b|\bmainargs\b/
    WEB_RE  = /\bimport\s+(?:akka\.http|play\.api|org\.http4s|cask|com\.twitter\.finatra|com\.linecorp\.armeria|zhttp|zio\.http)\b/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".scala").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)
          root_url = "cli://#{cli_binary_name(path)}"
          emit_env = !content.matches?(WEB_RE)
          pending_cmd_url = root_url
          in_children = false
          children_depth = 0
          content.each_line.with_index do |line, index|
            line_no = index + 1
            if (m = line.match(SCOPT_CMD)) || (m = line.match(DEC_CMD))
              pending_cmd_url = "#{root_url}/#{m[1]}"
              fetch_endpoint(endpoints, pending_cmd_url, path, line_no)
            end
            # scopt scopes a subcommand's opts inside `.children( ... )`; only
            # there do options bind to the subcommand. Outside, they (and any
            # trailing root opts after the block) bind to the root.
            in_children = true if line.includes?(".children(")
            target = in_children ? pending_cmd_url : root_url
            if (m = line.match(SCOPT_OPT)) || (m = line.match(DEC_OPT)) || (m = line.match(DEC_FLAG))
              fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "flag"))
            end
            if (m = line.match(SCOPT_ARG)) || (m = line.match(DEC_ARG))
              fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "argument"))
            end
            if in_children
              children_depth += line.count('(') - line.count(')')
              if children_depth <= 0
                in_children = false
                children_depth = 0
              end
            end
            if emit_env
              line.scan(SYS_ENV) do |em|
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
      stem = File.basename(path, ".scala")
      if stem == "Main" || stem == "main" || stem == "Cli" || stem == "App"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("/it/") || lower.includes?("spec.scala") || lower.includes?("test.scala")
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
