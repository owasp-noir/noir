require "yaml"
require "../../../models/analyzer"
require "../../engines/cli_endpoint_support"
require "../../../miniparsers/crystal_callee_extractor"
require "../../../detector/detectors/crystal/cli"

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

    # stdlib subcommand dispatch. `case ARGV.shift?` / `case ARGV[0]?` with
    # string `when` arms; `ARGV[0]? == "x"` / `ARGV == ["x", "--y"]` tests.
    ARGV_CASE      = /\bcase\s+ARGV(?:\.(?:shift|first)\??|\s*\[\s*0\s*\]\??)\s*$/
    ARGV_CASE_PEEK = /\bcase\s+ARGV(?:\s*\[|\.first\b)/
    WHEN_STRINGS   = /^\s*when\s+("[^"]*"(?:\s*,\s*"[^"]*")*)(?:\s+then\b|\s*$)/
    ARGV_SUB_EQ    = /\bARGV(?:\s*\[\s*0\s*\]\??|\.first\??)\s*[!=]=\s*"([^"]+)"/
    ARGV_ARRAY_EQ  = /\bARGV\s*[!=]=\s*\[([^\]]*)\]/
    ARGV_TAKE      = /\bARGV\.(?:first|shift)\b/
    ARGV_SPLAT     = /^\s*(\w+(?:\s*,\s*\w+)+)\s*=\s*ARGV\s*$/

    MARKERS = Detector::Crystal::Cli::MARKERS
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

    # A `case` on an ARGV selector being walked. `column` is its `when`
    # column (the first `when` sets it), `arm` the URLs the current arm
    # names, `named` whether any arm named a subcommand.
    private class ArgvCase
      property column : Int32? = nil
      property arm : Array(String)
      property? named = false
      getter parent : Array(String)
      getter line : Int32

      def initialize(@parent, @shifts : Bool, @line)
        @arm = @parent
      end

      # Maps a raw ARGV index onto the arm's own positions: an arm that named
      # a subcommand off a peeking selector (`ARGV[0]?`, `ARGV.first?`) still
      # has that subcommand at ARGV[0]. `else` and non-string arms keep it.
      def offset : Int32
        !@shifts && arm != parent ? -1 : 0
      end
    end

    private def scan(lines, path, root_url, endpoints, emit_env)
      current_url = root_url
      cases = [] of ArgvCase
      lines.each_with_index do |line, index|
        line_no = index + 1

        # ponytail: arms are scoped by indentation, which `crystal tool
        # format` makes reliable; unformatted code leaves the case early and
        # its params land on the parent command.
        unless cases.empty? || line.blank?
          indent = line.size - line.lstrip.size
          while frame = cases.last?
            frame.column = indent if frame.column.nil? && line.matches?(/^\s*when\b/)
            column = frame.column
            break if column && indent > column
            if column == indent && (m = line.match(/^\s*(when|else)\b/))
              frame.arm = m[1] == "else" ? frame.parent : case_arm(line, frame.parent, endpoints, path, line_no)
              frame.named = true if frame.arm != frame.parent
              break
            end
            close_case(cases.pop, endpoints, path)
          end
        end
        targets = cases.last?.try(&.arm) || [root_url]
        offset = cases.last?.try(&.offset) || 0

        if m = line.match(CLIM_SUB)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end
        if m = line.match(ADM_SUB)
          sub = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, sub, path, line_no)
        end

        if m = line.match(OPT_LONG) || line.match(OPT_SHORT)
          push_params(endpoints, targets, path, line_no, m[1].lstrip('-'), "flag")
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

        if line.includes?("ARGV")
          if line.matches?(ARGV_CASE)
            cases << ArgvCase.new(targets, !line.matches?(ARGV_CASE_PEEK), line_no)
          else
            argv_reads(line, targets, offset, endpoints, path, line_no)
          end
        end
        if emit_env
          line.scan(ENV_INDEX) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
          line.scan(ENV_FETCH) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
        end
      end
      cases.reverse_each { |frame| close_case(frame, endpoints, path) }
    end

    private def argv_reads(line, targets, offset, endpoints, path, line_no)
      line.scan(ARGV_SUB_EQ) { |em| argv_words([em[1]], targets, endpoints, path, line_no) }
      line.scan(ARGV_ARRAY_EQ) { |em| argv_words(em[1].scan(/"([^"]*)"/).map(&.[1]), targets, endpoints, path, line_no) }
      # An `ARGV[0]? == "x"` test names a subcommand, not a positional.
      rest = line.gsub(ARGV_SUB_EQ, "")
      positions = if m = rest.match(ARGV_INDEX)
                    [m[1].to_i]
                  elsif rest.matches?(ARGV_TAKE)
                    [0]
                  elsif m = rest.match(ARGV_SPLAT)
                    (0...m[1].split(',').size).to_a
                  else
                    [] of Int32
                  end
      positions.each do |position|
        push_params(endpoints, targets, path, line_no, "arg#{position + offset}", "argument") if position + offset >= 0
      end
    end

    # A case that never named a subcommand (`when nil`, `when /re/`, flags
    # only) reads its selector as the parent's first positional.
    private def close_case(frame, endpoints, path)
      push_params(endpoints, frame.parent, path, frame.line, "arg0", "argument") unless frame.named?
    end

    # A `when "a", "b"` arm: each non-flag string is a subcommand under
    # `parent`; a `"--help"` string is a flag of `parent` itself.
    private def case_arm(line, parent, endpoints, path, line_no) : Array(String)
      return parent unless m = line.match(WHEN_STRINGS)
      words = m[1].scan(/"([^"]*)"/).map(&.[1])
      words.select(&.starts_with?('-')).each { |flag| push_params(endpoints, parent, path, line_no, flag.lstrip('-'), "flag") }
      subs = words.reject { |word| word.empty? || word.starts_with?('-') }
      return parent if subs.empty?
      parent.flat_map { |url| subs.map { |sub| "#{url}/#{sub}" } }.tap(&.each { |url| fetch_endpoint(endpoints, url, path, line_no) })
    end

    # The words an ARGV comparison spells out: a leading non-flag word is a
    # subcommand, every `--flag` a flag of it (or of `targets` without one).
    private def argv_words(words, targets, endpoints, path, line_no)
      if (first = words.first?) && !first.empty? && !first.starts_with?('-')
        targets = targets.map { |url| "#{url}/#{first}" }
        targets.each { |url| fetch_endpoint(endpoints, url, path, line_no) }
      end
      words.select(&.starts_with?('-')).each { |flag| push_params(endpoints, targets, path, line_no, flag.lstrip('-'), "flag") }
    end

    private def push_params(endpoints, urls, path, line_no, name, type)
      urls.each { |url| fetch_endpoint(endpoints, url, path, line_no).push_param(Param.new(name, "", type)) }
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
