require "../../../models/analyzer"

module Analyzer::Groovy
  # Surfaces the command-line attack surface of Groovy programs as `cli://`
  # endpoints: the built-in CliBuilder (and picocli @Option) plus
  # System.getenv. Line-scan; root attribution (CliBuilder is flat), merged
  # by URL.
  class Cli < Analyzer
    CLI_OPT     = /\bcli\.([A-Za-z_]\w*)\s*\(([^)]*)/
    LONGOPT     = /longOpt:\s*['"]([^'"]+)['"]/
    OPTION_ATTR = /@Option\s*\(([^)]*)\)/
    GET_ENV     = /\bSystem\.getenv\s*\(\s*['"]([^'"]+)['"]/

    # CliBuilder methods that are not option definitions.
    NON_OPTION = Set{"parse", "usage", "with", "width", "header", "footer",
                     "stopAtNonOption", "expandArgumentFiles", "posix",
                     "errorWriter", "writer", "name"}

    MARKERS = /\bnew\s+CliBuilder\b|\bCliBuilder\s*\(|@picocli|@Command\b/
    WEB_RE  = /\bimport\s+(?:grails|org\.springframework)\b|@Controller\b|@RestController\b/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".groovy").each do |path|
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
            if m = line.match(CLI_OPT)
              unless NON_OPTION.includes?(m[1])
                name = line.match(LONGOPT).try(&.[1]) || m[1]
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "flag"))
              end
            end
            if m = line.match(OPTION_ATTR)
              if name = picocli_name(m[1])
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "flag"))
              end
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

    private def picocli_name(body : String) : String?
      tokens = [] of String
      body.scan(/"(--?[A-Za-z0-9][\w-]*)"/) { |m| tokens << m[1] }
      return if tokens.empty?
      (tokens.find(&.starts_with?("--")) || tokens.first).lstrip('-')
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".groovy")
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("spec.groovy") || lower.includes?("test.groovy")
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
