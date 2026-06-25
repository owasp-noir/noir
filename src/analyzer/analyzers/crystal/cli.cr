require "../../../models/analyzer"

module Analyzer::Crystal
  # Surfaces the command-line attack surface of Crystal programs as `cli://`
  # endpoints: stdlib OptionParser / ARGV / ENV plus the clim, admiral and
  # commander shards. One endpoint per (sub)command, params flag/argument/env,
  # merged by URL. Line-scan; subclasses Analyzer directly.
  class Cli < Analyzer
    OPTION_PARSER = /\bOptionParser\.(?:parse|new)\b/
    OPT_LONG      = /\.on\s*\(?[^)]*?["'](-{2}[A-Za-z0-9][\w-]*)/
    OPT_SHORT     = /\.on\s*\(\s*["'](-[A-Za-z0-9])(?:["' =]|\))/
    ARGV_INDEX    = /\bARGV\s*\[\s*(\d+)\s*\]/
    ENV_INDEX     = /\bENV\s*\[\s*["']([^"']+)["']\s*\]/
    ENV_FETCH     = /\bENV\.fetch\s*\(\s*["']([^"']+)["']/

    CLIM_SUB      = /^\s*sub\s+["']([A-Za-z0-9][\w-]*)["']/
    CLIM_OPTION   = /^\s*option\s+["'](-{1,2}[A-Za-z0-9][\w-]*)/
    CLIM_ARGUMENT = /^\s*argument\s+["']([A-Za-z0-9][\w-]*)/
    ADM_FLAG      = /^\s*define_flag\s+([A-Za-z_]\w*)/
    ADM_ARG       = /^\s*define_argument\s+([A-Za-z_]\w*)/
    ADM_SUB       = /\bregister_sub_command\s+([A-Za-z0-9_]+)/

    MARKERS = /\bOptionParser\.(?:parse|new)\b|\bARGV\s*\[\s*\d+\s*\]|<\s*Clim\b|<\s*Admiral::Command\b|\bCommander::Command\b|\brequire\s+"(?:clim|admiral|commander)"/
    WEB_RE  = /\brequire\s+"(?:kemal|amber|lucky|grip|marten)"|HTTP::Server\.new|\bKemal\b|Amber::Server/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".cr").each do |path|
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
      current_url = root_url
      lines.each_with_index do |line, index|
        line_no = index + 1

        if m = line.match(CLIM_SUB)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end
        if m = line.match(ADM_SUB)
          sub = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, sub, path, line_no)
        end

        if m = line.match(OPT_LONG)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        elsif m = line.match(OPT_SHORT)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        end
        if m = line.match(CLIM_OPTION)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1].lstrip('-'), "", "flag"))
        end
        if m = line.match(CLIM_ARGUMENT)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end
        if m = line.match(ADM_FLAG)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(ADM_ARG)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end

        if m = line.match(ARGV_INDEX)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
        end
        if emit_env
          line.scan(ENV_INDEX) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
          line.scan(ENV_FETCH) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
        end
      end
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".cr")
      if stem == "main" || stem == "cli" || stem == "app"
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
