require "../../../models/analyzer"

module Analyzer::Haskell
  # Surfaces the command-line attack surface of Haskell programs as `cli://`
  # endpoints: optparse-applicative (long/argument/command) plus getEnv reads.
  # Line-scan, merged by URL.
  class Cli < Analyzer
    LONG     = /(?<![A-Za-z0-9_'])long\s+"([A-Za-z0-9][\w-]*)"/
    ARGUMENT = /(?<![A-Za-z0-9_'])argument\b.*?\bmetavar\s+"([A-Za-z0-9][\w-]*)"/
    COMMAND  = /(?<![A-Za-z0-9_'])command\s+"([A-Za-z0-9][\w-]*)"/
    GET_ENV  = /(?<![A-Za-z0-9_'])(?:getEnv|lookupEnv)\s+"([A-Za-z0-9_]\w*)"/

    MARKERS = /\bimport\s+(?:qualified\s+)?Options\.Applicative\b|\b(?:execParser|strOption|subparser|hsubparser)\b|\bimport\s+(?:qualified\s+)?System\.Console\.(?:GetOpt|CmdArgs)\b|\bgetArgs\b/
    WEB_RE  = /\bimport\s+(?:qualified\s+)?(?:Web\.Scotty|Servant|Yesod|Network\.Wai)\b/

    def analyze
      endpoints = {} of String => Endpoint
      [".hs", ".lhs"].each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cli_test_path?(path)
          next unless File.exists?(path)
          begin
            content = read_file_content(path)
            next unless content.matches?(MARKERS)
            root_url = "cli://#{cli_binary_name(path)}"
            emit_env = !content.matches?(WEB_RE)
            content.each_line.with_index do |line, index|
              line_no = index + 1
              # optparse-applicative defines subcommand option parsers in
              # separate top-level bindings, so a sticky cursor would
              # misattribute later root globals. Scope a `command "x"` only to
              # options on the SAME line (the common inline shape); otherwise
              # attribute to the root.
              target = root_url
              if m = line.match(COMMAND)
                target = "#{root_url}/#{m[1]}"
                fetch_endpoint(endpoints, target, path, line_no)
              end
              if m = line.match(LONG)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(ARGUMENT)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1].downcase, "", "argument"))
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
      if stem == "Main" || stem == "main" || stem == "Cli" || stem == "App"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("_spec.")
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
