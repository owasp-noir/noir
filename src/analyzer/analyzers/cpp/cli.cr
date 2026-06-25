require "../../../models/analyzer"

module Analyzer::Cpp
  # Surfaces the command-line attack surface of C++ programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers CLI11, getopt/getopt_long, cxxopts,
  # boost::program_options and gflags, plus gated getenv reads.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. There is no C++ engine, so it subclasses Analyzer directly.
  class Cli < Analyzer
    EXTS = [".cpp", ".cc", ".cxx", ".c++", ".hpp", ".hh", ".hxx"]

    # CLI11. Variable-mapped: an option/flag binds to its receiver variable
    # (app vs a subcommand), so a root option declared after a subcommand
    # isn't mis-attributed to it.
    APP_DECL       = /\bCLI::App\s+(\w+)/
    SUBCOMMAND_VAR = /(\w+)\s*=\s*\w+\s*(?:\.|->)\s*add_subcommand\s*\(\s*"([^"]+)"/
    SUBCOMMAND     = /(?:\.|->)\s*add_subcommand\s*\(\s*"([^"]+)"/
    ADD_OPTION     = /(\w+)\s*(?:\.|->)\s*add_option\s*\(\s*"([^"]+)"/
    ADD_FLAG       = /(\w+)\s*(?:\.|->)\s*add_flag\s*\(\s*"([^"]+)"/

    # getopt_long struct option entries + short spec.
    LONG_OPT_ENTRY = /\{\s*"([A-Za-z0-9][\w-]*)"\s*,\s*(?:no_argument|required_argument|optional_argument|\d)/
    GETOPT_CALL    = /\bgetopt(?:_long)?\s*\([^,]+,[^,]+,\s*"([^"]*)"/

    # cxxopts / boost::program_options option specs are bare `("name", ...)`
    # grouping/chaining calls — the `(` is preceded by `)` or whitespace, not
    # an identifier (which would make it a helper call like default_value(...)).
    OPTS_PAIR = /(?<!\w)\(\s*"([A-Za-z0-9][\w,-]*)"\s*,/
    OPTS_CALL = /add_options\s*\(\s*\)/

    # gflags.
    GFLAGS_DEF = /\bDEFINE_(?:string|int32|int64|bool|double|uint32|uint64)\s*\(\s*(\w+)/

    GETENV   = /\b(?:std::)?getenv\s*\(\s*"([^"]+)"/
    ARGV_IDX = /\bargv\s*\[\s*(\d+)\s*\]/

    CLI_MARKERS = ["CLI::App", "getopt", "struct option", "cxxopts::", "program_options", "DEFINE_string", "DEFINE_int", "DEFINE_bool"]
    WEB_RE      = /\b(?:Crow|crow|drogon|httplib|oatpp)\b|Crow::|drogon::|httplib::|oatpp::/

    def analyze
      endpoints = {} of String => Endpoint

      EXTS.each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cpp_test_path?(path)
          next unless File.exists?(path)

          begin
            content = read_file_content(path)
            next unless CLI_MARKERS.any? { |m| content.includes?(m) }

            binary = cpp_binary_name(path)
            root_url = "cli://#{binary}"
            emit_env = !content.matches?(WEB_RE)
            scan(content.lines, path, root_url, endpoints, emit_env)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end

      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cpp_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("/tests/") ||
        lower.includes?("_test.") || lower.includes?("test_") || lower.includes?(".test.")
    end

    private def cpp_binary_name(path : String) : String
      stem = File.basename(path)
      EXTS.each { |ext| stem = stem[0...-ext.size] if stem.ends_with?(ext) }
      if stem == "main" || stem == "app" || stem == "cli"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def scan(lines : Array(String), path : String, root_url : String,
                     endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url            # cursor for bare add_subcommand chains
      var_urls = {} of String => String # CLI11 App / subcommand variables
      in_opts_block = false

      lines.each_with_index do |line, index|
        line_no = index + 1

        # CLI11 variables: `CLI::App app{...}` -> root; `auto* x = ....add_subcommand("y")` -> sub.
        if m = line.match(APP_DECL)
          var_urls[m[1]] = root_url
        end
        if m = line.match(SUBCOMMAND_VAR)
          url = "#{root_url}/#{m[2]}"
          var_urls[m[1]] = url
          current_url = url
          fetch_endpoint(endpoints, url, path, line_no)
        elsif m = line.match(SUBCOMMAND)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end

        # CLI11 add_option("-p,--port" | "config") / add_flag("-v,--verbose"),
        # attributed by the receiver variable.
        if m = line.match(ADD_OPTION)
          push_named(endpoints, var_urls[m[1]]? || current_url, path, line_no, m[2])
        end
        if m = line.match(ADD_FLAG)
          name = opt_long(m[2])
          fetch_endpoint(endpoints, var_urls[m[1]]? || current_url, path, line_no).push_param(Param.new(name, "", "flag")) unless name.empty?
        end

        # getopt_long struct option entries + short spec (root flags).
        if m = line.match(LONG_OPT_ENTRY)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(GETOPT_CALL)
          parse_getopt_short(m[1], fetch_endpoint(endpoints, root_url, path, line_no))
        end

        # cxxopts / boost::program_options option pairs — `scan` so every pair
        # on a chained line is captured.
        in_opts_block = true if line.matches?(OPTS_CALL)
        if in_opts_block
          line.scan(OPTS_PAIR) do |om|
            name = opt_long(om[1])
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "flag")) unless name.empty?
          end
        end
        in_opts_block = false if in_opts_block && line.includes?(";")

        # gflags.
        if m = line.match(GFLAGS_DEF)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end

        if emit_env
          line.scan(GETENV) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
        end
      end
    end

    # A CLI11 add_option name starting with `-` is an option/flag; otherwise
    # it's a positional argument.
    private def push_named(endpoints : Hash(String, Endpoint), url : String,
                           path : String, line_no : Int32, raw : String)
      if raw.starts_with?("-")
        name = opt_long(raw)
        fetch_endpoint(endpoints, url, path, line_no).push_param(Param.new(name, "", "flag")) unless name.empty?
      else
        fetch_endpoint(endpoints, url, path, line_no).push_param(Param.new(raw, "", "argument"))
      end
    end

    # Picks the long form from a comma/dash option spec ("p,port" /
    # "-p,--port" / "--port") and strips dashes.
    private def opt_long(raw : String) : String
      parts = raw.split(',').map(&.strip)
      long = parts.find(&.starts_with?("--")) || parts.find(&.size.>(1)) || parts.first?
      (long || "").lstrip('-')
    end

    private def parse_getopt_short(spec : String, endpoint : Endpoint)
      spec.each_char do |ch|
        next if ch == ':' || ch == '+' || ch == '-'
        endpoint.push_param(Param.new(ch.to_s, "", "flag"))
      end
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
