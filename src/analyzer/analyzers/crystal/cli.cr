require "yaml"
require "../../../models/analyzer"
require "../../engines/cli_endpoint_support"
require "../../../miniparsers/crystal_callee_extractor"

module Analyzer::Crystal
  # Surfaces the command-line attack surface of Crystal programs as `cli://`
  # endpoints: stdlib OptionParser / ARGV / ENV plus the clim, admiral and
  # commander shards. One endpoint per (sub)command, params flag/argument/env,
  # merged by URL. Line-scan; subclasses Analyzer directly.
  class Cli < Analyzer
    analyzer_for "crystal_cli"

    include CliEndpointSupport

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
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          # Comment-cut first: a doc comment's `ARGV[0]` or `parser.on`
          # example is not the program reading input.
          lines = read_file_content(path).lines.map { |line| Noir::CrystalCalleeExtractor.strip_comment(line) }
          content = lines.join('\n')
          next unless content.matches?(MARKERS)
          root_url = "cli://#{cli_binary_name(path)}"
          emit_env = !content.matches?(WEB_RE)
          scan(lines, path, root_url, endpoints, emit_env)
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end
      @result.concat(cli_endpoints(endpoints))
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

    REQUIRE_RE = /^\s*require\s+"(\.{1,2}\/[^"*]+)"/

    @shard_target_names : Hash(String, String)?

    # Each `.cr` file a `shard.yml` target builds, by expanded path => the
    # target's name: its `main:` and every file that main reaches through
    # relative `require`s. A file two targets reach names neither.
    private def shard_target_names : Hash(String, String)
      @shard_target_names ||= begin
        reached = {} of String => Set(String)
        get_files_by_basename("shard.yml").each do |manifest|
          targets = YAML.parse(read_file_content(manifest))["targets"]?.try(&.as_h?) rescue nil
          next unless targets
          dir = File.dirname(Noir::PathScope.expand(manifest))
          targets.each do |name, target|
            main = target["main"]?.try(&.as_s?) rescue nil
            next unless main
            pending = [File.expand_path(main, dir)]
            seen = Set(String).new
            while file = pending.pop?
              next unless seen.add?(file) && seen.size <= 512 && File.file?(file)
              (reached[file] ||= Set(String).new) << name.to_s
              (read_file_content(file) rescue "").each_line do |line|
                if match = line.match(REQUIRE_RE)
                  required = File.expand_path(match[1], File.dirname(file))
                  pending << (required.ends_with?(".cr") ? required : "#{required}.cr")
                end
              end
            end
          end
        end
        names = {} of String => String
        reached.each { |file, targets| names[file] = targets.first if targets.size == 1 }
        names
      end
    end

    private def cli_binary_name(path : String) : String
      if name = shard_target_names[Noir::PathScope.expand(path)]?
        return name
      end
      stem = File.basename(path, ".cr")
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
      lower.includes?("_spec.") || lower.includes?("/test/")
    end
  end
end
