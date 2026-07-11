require "../../../models/analyzer"

module Analyzer::Lua
  # Surfaces the command-line attack surface of Lua programs as `cli://`
  # endpoints: the argparse library (option/flag/argument/command, attributed
  # by receiver variable), the cliargs (lua_cliargs) library
  # (add_argument/add_option/add_flag, attributed by receiver variable), plus
  # `arg` indexing and os.getenv. Line-scan, merged by URL.
  class Cli < Analyzer
    ARGPARSE_CTOR = /(?:local\s+)?([A-Za-z_]\w*)\s*=\s*argparse\s*\(\s*(?:['"]([^'"]*)['"])?/
    SUBCOMMAND    = /(?:local\s+)?(?:([A-Za-z_]\w*)\s*=\s*)?([A-Za-z_]\w*)\s*:\s*command\s*\(\s*['"]([^'"]+)['"]/
    OPTION        = /([A-Za-z_]\w*)\s*:\s*(?:option|flag)\s*\(\s*['"]([^'"]+)['"]/
    ARGUMENT      = /([A-Za-z_]\w*)\s*:\s*argument\s*\(\s*['"]([^'"]+)['"]/
    ARG_IDX       = /\barg\s*\[\s*(\d+)\s*\]/
    GET_ENV       = /\bos\.getenv\s*\(\s*['"]([^'"]+)['"]/

    CLIARGS_CTOR   = /(?:local\s+)?([A-Za-z_]\w*)\s*=\s*require\s*\(?\s*['"]cliargs['"]/
    CLIARGS_NAME   = /([A-Za-z_]\w*)\s*:\s*set_name\s*\(\s*['"]([^'"]+)['"]/
    CLIARGS_ARG    = /([A-Za-z_]\w*)\s*:\s*add_argument\s*\(\s*['"]([^'"]+)['"]/
    CLIARGS_OPTION = /([A-Za-z_]\w*)\s*:\s*add_option\s*\(\s*['"]([^'"]+)['"]/
    CLIARGS_FLAG   = /([A-Za-z_]\w*)\s*:\s*add_flag\s*\(\s*['"]([^'"]+)['"]/

    MARKERS = /\brequire\s*\(?\s*['"]argparse['"]|\bargparse\s*\(|\barg\s*\[\s*\d+\s*\]|\brequire\s*\(?\s*['"]cliargs['"]/
    WEB_RE  = /\brequire\s*\(?\s*['"](?:lapis|lor)['"]/
    # `cli_test_path?`'s two OR-ed String#includes? scans, folded into one
    # precompiled union so the per-file boolean gate costs a single PCRE2
    # match instead of up to two naive substring scans.
    TEST_PATH_RE = Regex.union("_spec.", "/test/")

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".lua").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)

          # Pre-scan: variables actually bound to `require("cliargs")`.
          # set_name/add_argument/add_option/add_flag are only trusted when
          # their receiver is one of these — never a same-named method on an
          # unrelated table (e.g. a `logger:set_name(...)` or a
          # `menu:add_option(...)` that happens to sit in the same file).
          cliargs_vars = Set(String).new
          content.each_line do |line|
            if m = line.match(CLIARGS_CTOR)
              cliargs_vars << m[1]
            end
          end

          # binary: argparse("name") if present, else cliargs :set_name("name")
          # on a tracked cliargs receiver, else file stem.
          argparse_name = content.match(/argparse\s*\(\s*['"]([^'"]+)['"]/)
          cliargs_name = nil
          unless argparse_name
            content.scan(CLIARGS_NAME) do |m|
              if cliargs_vars.includes?(m[1])
                cliargs_name = m
                break
              end
            end
          end
          binary = if argparse_name
                     argparse_name[1]
                   elsif cliargs_name
                     cliargs_name[2]
                   else
                     cli_binary_name(path)
                   end
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_RE)
          var_urls = {} of String => String

          content.each_line.with_index do |line, index|
            line_no = index + 1
            if m = line.match(ARGPARSE_CTOR)
              var_urls[m[1]] = root_url
            end
            if m = line.match(SUBCOMMAND)
              url = "#{root_url}/#{m[3]}"
              var_urls[m[1]] = url if m[1]?
              fetch_endpoint(endpoints, url, path, line_no)
            end
            if (m = line.match(OPTION)) && var_urls.has_key?(m[1])
              fetch_endpoint(endpoints, var_urls[m[1]], path, line_no).push_param(Param.new(opt_long(m[2]), "", "flag"))
            end
            if (m = line.match(ARGUMENT)) && var_urls.has_key?(m[1])
              fetch_endpoint(endpoints, var_urls[m[1]], path, line_no).push_param(Param.new(m[2], "", "argument"))
            end
            if m = line.match(ARG_IDX)
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
            end
            if m = line.match(CLIARGS_CTOR)
              var_urls[m[1]] = root_url
            end
            if (m = line.match(CLIARGS_ARG)) && var_urls.has_key?(m[1])
              fetch_endpoint(endpoints, var_urls[m[1]], path, line_no).push_param(Param.new(m[2], "", "argument"))
            end
            if (m = line.match(CLIARGS_OPTION)) && var_urls.has_key?(m[1])
              fetch_endpoint(endpoints, var_urls[m[1]], path, line_no).push_param(Param.new(cliargs_opt_long(m[2]), "", "flag"))
            end
            if (m = line.match(CLIARGS_FLAG)) && var_urls.has_key?(m[1])
              fetch_endpoint(endpoints, var_urls[m[1]], path, line_no).push_param(Param.new(cliargs_opt_long(m[2]), "", "flag"))
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

    # argparse alias spec ("-p --port" / "--port") -> long name without dashes.
    private def opt_long(raw : String) : String
      tokens = raw.split(/\s+/)
      long = tokens.find(&.starts_with?("--")) || tokens.find(&.starts_with?("-")) || tokens.first?
      (long || raw).lstrip('-')
    end

    # cliargs alias spec ("-o, --output=DEST" / "-v, --[no-]verbose") -> long name.
    private def cliargs_opt_long(raw : String) : String
      tokens = raw.split(',').map(&.strip)
      long = tokens.find(&.starts_with?("--")) || tokens.find(&.starts_with?("-")) || tokens.first?
      name = (long || raw).lstrip('-')
      name = name.gsub("[no-]", "")
      name.split('=').first
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".lua")
      if stem == "main" || stem == "cli" || stem == "init"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      path.downcase.matches?(TEST_PATH_RE)
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
