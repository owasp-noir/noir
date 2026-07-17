require "../../../models/analyzer"

module Analyzer::Cpp
  # Surfaces the command-line attack surface of C++ programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers CLI11, getopt/getopt_long, cxxopts,
  # boost::program_options, gflags, Abseil Flags and p-ranav/argparse, plus
  # gated getenv reads.
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

    # p-ranav/argparse. Declare-then-register style: an ArgumentParser
    # variable's role (root vs subcommand) is only known once it's observed
    # either as the receiver of `.parse_args(argc, argv)` / owner side of
    # `.add_subparser(...)`, or by elimination when it's the file's only
    # declared parser. Resolved once per file in `resolve_argparse_vars`
    # before options are attributed, so declaration order in the file never
    # decides which parser is root (a helper-function-local parser can never
    # be mistaken for the real root).
    ARGPARSE_DECL      = /\bargparse::ArgumentParser\s+(\w+)\s*\(\s*"([^"]+)"/
    ARGPARSE_ADD_ARG   = /(\w+)\s*(?:\.|->)\s*add_argument\s*\(\s*"([^"]+)"(?:\s*,\s*"([^"]+)")?/
    ARGPARSE_SUBPARSER = /(\w+)\s*(?:\.|->)\s*add_subparser\s*\(\s*(\w+)\s*\)/
    ARGPARSE_PARSE     = /(\w+)\s*(?:\.|->)\s*parse_args\s*\(\s*argc\s*,\s*argv\s*\)/

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

    # Abseil Flags. `ABSL_FLAG(type, name, default, help)` — the type is
    # matched with a depth-aware manual scan (see `absl_flag_names`) rather
    # than a character-class regex, so a template type with a top-level
    # comma (e.g. `std::map<std::string,int>`) doesn't truncate/misparse the
    # name field.
    ABSL_FLAG_MARK = /\bABSL_FLAG\s*\(/

    GETENV   = /\b(?:std::)?getenv\s*\(\s*"([^"]+)"/
    ARGV_IDX = /\bargv\s*\[\s*(\d+)\s*\]/

    # Whitespace-tolerant substring markers (no trailing "(" on macro-style
    # entries) so this gate can never diverge from what the extraction
    # regexes above actually accept, e.g. `ABSL_FLAG (int32_t, ...)` with a
    # space before the paren is valid C++ and must not be silently skipped.
    # Precompiled as a single Regex.union so the per-file evidence gate costs
    # one PCRE2 match instead of up to ten naive substring scans.
    CLI_MARKERS_RE = Regex.union("CLI::App", "getopt", "struct option", "cxxopts::", "program_options",
      "DEFINE_string", "DEFINE_int", "DEFINE_bool", "ABSL_FLAG", "argparse::ArgumentParser")
    WEB_RE = /\b(?:Crow|crow|drogon|httplib|oatpp)\b|Crow::|drogon::|httplib::|oatpp::/

    # Precompiled union for the per-file test-path skip gate (cpp_test_path?),
    # matched via String#matches? instead of five naive substring scans.
    CPP_TEST_PATH_RE = Regex.new(
      Regex.union("/test/", "/tests/", "_test.", "test_", ".test.").source,
      Regex::Options::IGNORE_CASE
    )

    def analyze
      endpoints = {} of String => Endpoint

      EXTS.each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cpp_test_path?(path)
          next unless File.exists?(path)

          begin
            content = read_file_content(path)
            next unless content.matches?(CLI_MARKERS_RE)

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
      path.matches?(CPP_TEST_PATH_RE)
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
      argparse_var_urls = resolve_argparse_vars(lines, path, root_url, endpoints)
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

        # p-ranav/argparse add_argument("-v","--verbose") / add_argument("input"),
        # attributed by the receiver variable. Strict lookup: a receiver that
        # `resolve_argparse_vars` never bound to a root/subcommand url (e.g. a
        # parser built by an unrelated helper function) is dropped rather than
        # falling back to the file's root — no stray-match root fallback.
        if m = line.match(ARGPARSE_ADD_ARG)
          if url = argparse_var_urls[m[1]]?
            raw = m[3]? ? "#{m[2]},#{m[3]}" : m[2]
            push_named(endpoints, url, path, line_no, raw)
          end
        end

        # gflags.
        if m = line.match(GFLAGS_DEF)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end

        # Abseil Flags: ABSL_FLAG(type, name, default, help) — root flags.
        absl_flag_names(line).each do |flag_name|
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(flag_name, "", "flag"))
        end

        # raw argv positionals. `scan` so every argv[N] on one line surfaces
        # and the argv[0]-program-name skip is applied per index, not just to
        # the first match (`execl(argv[0], argv[1], ...)` must still yield arg1).
        line.scan(ARGV_IDX) do |am|
          next if am[1] == "0"
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{am[1]}", "", "argument"))
        end

        if emit_env
          line.scan(GETENV) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
        end
      end
    end

    # Resolves p-ranav/argparse ArgumentParser variables to their root/
    # subcommand urls in a single pre-pass over the whole file, so that
    # declaration order (a helper function's local parser declared above
    # `main`) can never decide which variable is the real root — only an
    # explicit linking call can:
    #   - a var seen as the receiver of `.parse_args(argc, argv)` (and never
    #     itself a subparser child) is root;
    #   - otherwise a var seen as the owner (receiver) side of
    #     `.add_subparser(child)` (and never itself a child) is root;
    #   - otherwise, if there is exactly one declared parser that is never a
    #     child, it's root by elimination (the common no-subcommands case).
    # A parser var that resolves to neither role (e.g. a factory helper's
    # local parser, never linked or parsed) is left unbound — its
    # add_argument calls are dropped in `scan` rather than mis-attributed.
    private def resolve_argparse_vars(lines : Array(String), path : String, root_url : String,
                                      endpoints : Hash(String, Endpoint)) : Hash(String, String)
      declared = {} of String => String          # var -> display name
      links = [] of Tuple(String, String, Int32) # parent_var, child_var, line_no
      parse_vars = [] of String

      lines.each_with_index do |line, index|
        if m = line.match(ARGPARSE_DECL)
          declared[m[1]] = m[2] unless declared.has_key?(m[1])
        end
        if m = line.match(ARGPARSE_SUBPARSER)
          links << {m[1], m[2], index + 1}
        end
        if m = line.match(ARGPARSE_PARSE)
          parse_vars << m[1]
        end
      end

      var_urls = {} of String => String
      return var_urls if declared.empty?

      child_vars = links.map { |l| l[1] }
      owner_vars = links.map { |l| l[0] }

      root_var = parse_vars.find { |v| declared.has_key?(v) && !child_vars.includes?(v) }
      root_var ||= owner_vars.find { |v| declared.has_key?(v) && !child_vars.includes?(v) }
      if root_var.nil?
        candidates = declared.keys.reject { |v| child_vars.includes?(v) }
        root_var = candidates.first if candidates.size == 1
      end
      return var_urls if root_var.nil?

      var_urls[root_var] = root_url
      links.each do |link|
        parent, child, line_no = link
        next unless parent == root_var # single-level subcommand nesting only
        next unless name = declared[child]?
        url = "#{root_url}/#{name}"
        var_urls[child] = url
        fetch_endpoint(endpoints, url, path, line_no)
      end
      var_urls
    end

    # Extracts flag names from `ABSL_FLAG(type, name, default, help)` on a
    # line via a depth-aware manual scan rather than a character-class
    # regex, so a template type containing a top-level comma (e.g.
    # `std::map<std::string,int>`) doesn't break extraction of the name
    # field: `<`/`(` open a nesting level, `>`/`)` close one, and only a
    # comma at depth 0 separates macro arguments.
    private def absl_flag_names(line : String) : Array(String)
      names = [] of String
      offset = 0
      # Lazily materialized on the first match: String#[](Int) / #[](Range)
      # walk the UTF-8 buffer from the start on every call for any line
      # containing a multi-byte char, turning this scan into O(n^2)/O(n^3).
      # Array(Char) indexing/slicing is O(1)/O(k), so once a line actually
      # has an ABSL_FLAG( match, the loop below stays O(n) overall. Lines
      # without a match (the overwhelming majority in a scan) never pay for
      # the array allocation at all.
      chars = nil

      while offset <= line.size && (m = line.match(ABSL_FLAG_MARK, offset))
        chars ||= line.chars
        args_start = m.end
        fields = [] of String
        depth = 0
        field_start = args_start
        i = args_start
        closed_at = nil

        while i < chars.size
          case chars[i]
          when '(', '<'
            depth += 1
          when ')'
            if depth == 0
              fields << chars[field_start...i].join
              closed_at = i
              break
            end
            depth -= 1
          when '>'
            depth -= 1 if depth > 0
          when ','
            if depth == 0
              fields << chars[field_start...i].join
              field_start = i + 1
            end
          end
          i += 1
        end

        if fields.size >= 2
          name = fields[1].strip
          names << name if name.matches?(/\A\w+\z/)
        end

        offset = closed_at ? closed_at + 1 : args_start + 1
      end
      names
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
