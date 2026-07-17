require "../../../models/analyzer"
require "../../engines/php_engine"

module Analyzer::Php
  # Surfaces the command-line attack surface of PHP programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers Symfony Console, Laravel Artisan
  # (`$signature`), Robo (`@command` docblocks) and WP-CLI, plus builtin
  # getopt / $argv / $_ENV / getenv.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. Subclasses Analyzer directly (PhpEngine is abstract) and reuses
  # PhpEngine.test_path? to skip tests.
  class Cli < Analyzer
    SET_NAME     = /\$this->setName\s*\(\s*['"]([^'"]+)['"]/
    DEFAULT_NAME = /protected\s+(?:static\s+)?\$defaultName\s*=\s*['"]([^'"]+)['"]/
    AS_COMMAND   = /#\[\s*AsCommand\s*\(\s*name\s*:\s*['"]([^'"]+)['"]/
    ADD_ARGUMENT = /->\s*addArgument\s*\(\s*['"]([^'"]+)['"]/
    ADD_OPTION   = /->\s*addOption\s*\(\s*['"]([^'"]+)['"]/
    GET_OPTION   = /\$input->getOption\s*\(\s*['"]([^'"]+)['"]/
    GET_ARGUMENT = /\$input->getArgument\s*\(\s*['"]([^'"]+)['"]/

    GETOPT      = /\bgetopt\s*\(\s*(['"])([^'"]*)\1\s*(?:,\s*\[([^\]]*)\])?/
    ARGV_INDEX  = /\$argv\s*\[\s*(\d+)\s*\]/
    ENV_BRACKET = /\$_ENV\s*\[\s*['"]([^'"]+)['"]\s*\]/
    GETENV      = /\bgetenv\s*\(\s*['"]([^'"]+)['"]/

    WEB_FRAMEWORK_RE = /\buse\s+(?:Illuminate\\(?:Foundation|Http|Routing)|Symfony\\Bundle\\FrameworkBundle|Symfony\\Component\\HttpFoundation|Symfony\\Component\\HttpKernel|Slim\\(?:App|Factory)|Laminas\\(?:Mvc|Mezzio)|Mezzio\\|Cake\\(?:Routing|Http)|Hyperf\\HttpServer)\b|extends\s+AbstractController\b/

    # Laravel Artisan: `protected $signature = '...'`. The value is the
    # Symfony-Console-flavored mini-grammar Artisan parses itself:
    # `name {arg} {arg? : desc} {arg=default} {--flag} {--flag=default : desc}`.
    ARTISAN_SIGNATURE = /protected\s+(?:static\s+)?\$signature\s*=\s*(['"])((?:\\.|(?!\1).)*)\1/
    ARTISAN_TOKEN     = /\{\s*([^{}]*?)\s*\}/

    # Robo (consolidation/Robo task runner): a `@command <name>` docblock
    # tag binds to the *very next* method signature only — never sticky.
    ROBO_MARKER        = /Robo\\Tasks\b/
    ROBO_COMMAND_TAG   = /@command\s+(\S+)/
    ROBO_FUNCTION_LINE = /\bfunction\s+\w+\s*\(([^)]*)\)/

    # WP-CLI: `WP_CLI::add_command('foo bar', 'Foo_Bar_Command')` registers
    # a class as a command. Only the method whose OWN signature is the
    # conventional `($args, $assoc_args)` callback is scanned for params —
    # never the whole class body.
    WP_MARKER            = /WP_CLI(?:_Command)?\b/
    WP_ADD_COMMAND       = /WP_CLI::add_command\s*\(\s*(['"])((?:\\.|(?!\1).)*)\1\s*,\s*(?:new\s+)?['"]?(\w+)/
    WP_CLASS_LINE        = /\bclass\s+(\w+)/
    WP_METHOD_LINE       = /\bfunction\s+\w+\s*\((?=[^)]*\$args\b)(?=[^)]*\$assoc_args\b)[^)]*\)/
    WP_ARGS_INDEX        = /\$args\s*\[\s*(\d+)\s*\]/
    WP_ASSOC_ARG_BRACKET = /\$assoc_args\s*\[\s*['"]([^'"]+)['"]\s*\]/
    WP_FLAG_VALUE        = /get_flag_value\s*\(\s*\$assoc_args\s*,\s*['"]([^'"]+)['"]/

    # Cheap file-level reject before the precise multi-regex evidence
    # check. Every accepted CLI shape contains at least one of these
    # literals.
    CLI_HINT_RE = Regex.union(
      "Symfony\\Component\\Console",
      "extends Command",
      "AsCommand",
      "getopt",
      "$argv",
      "League\\CLImate",
      "Minicli\\",
      "$signature",
      "Robo\\Tasks",
      "WP_CLI",
    )

    def analyze
      endpoints = {} of String => Endpoint

      get_files_by_extension(".php").each do |path|
        next if File.directory?(path)
        next if PhpEngine.test_path?(path)

        begin
          content = read_file_content(path)
          next unless content.matches?(CLI_HINT_RE)
          next unless cli_evidence?(content)

          binary = php_binary_name(path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_FRAMEWORK_RE)
          has_artisan = content.matches?(ARTISAN_SIGNATURE)
          has_robo = content.matches?(ROBO_MARKER)
          has_wp = content.matches?(WP_MARKER)
          lines = content.lines

          scan(lines, path, root_url, endpoints, emit_env)
          scan_artisan(lines, path, root_url, endpoints) if has_artisan
          scan_robo(lines, path, root_url, endpoints) if has_robo
          scan_wp_cli(lines, path, root_url, endpoints) if has_wp
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_evidence?(content : String) : Bool
      content.includes?("Symfony\\Component\\Console") || content.matches?(/\bextends\s+Command\b/) ||
        content.matches?(AS_COMMAND) || content.matches?(GETOPT) || content.matches?(ARGV_INDEX) ||
        content.includes?("League\\CLImate") || content.includes?("Minicli\\") ||
        content.matches?(ARTISAN_SIGNATURE) || content.matches?(ROBO_MARKER) ||
        content.matches?(WP_ADD_COMMAND) || content.matches?(/extends\s+WP_CLI_Command\b/)
    end

    private def php_binary_name(path : String) : String
      base = @base_path.empty? ? File.dirname(path) : @base_path
      name = File.basename(File.expand_path(base))
      name.empty? ? File.basename(path, ".php") : name
    end

    private def scan(lines : Array(String), path : String, root_url : String,
                     endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url

      lines.each_with_index do |line, index|
        line_no = index + 1

        # Symfony command name (setName / $defaultName / #[AsCommand]).
        if m = line.match(SET_NAME) || line.match(DEFAULT_NAME) || line.match(AS_COMMAND)
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end

        if m = line.match(ADD_OPTION) || line.match(GET_OPTION)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(ADD_ARGUMENT) || line.match(GET_ARGUMENT)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end

        # builtin getopt: short spec + optional long-opt array (root flags).
        if m = line.match(GETOPT)
          parse_getopt_short(m[2], fetch_endpoint(endpoints, root_url, path, line_no))
          if longs = m[3]?
            longs.scan(/['"]([^'"]+)['"]/) do |lm|
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(lm[1].rstrip(':'), "", "flag"))
            end
          end
        end

        if m = line.match(ARGV_INDEX)
          # $argv[0] is the script name, not input.
          unless m[1] == "0"
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
          end
        end

        if emit_env
          line.scan(ENV_BRACKET) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
          line.scan(GETENV) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
        end
      end
    end

    # Laravel Artisan `protected $signature = '...'` mini-grammar. The
    # first whitespace-delimited token is the command name; every
    # `{...}` token after it is an argument (or `--`-prefixed option).
    # Each token may carry an idiomatic ` : description` suffix that must
    # be stripped before any of the `=`/`?`/`*` modifier handling, or the
    # extracted name ends up containing the whole description string.
    private def scan_artisan(lines : Array(String), path : String, root_url : String,
                             endpoints : Hash(String, Endpoint))
      lines.each_with_index do |line, index|
        line_no = index + 1
        next unless m = line.match(ARTISAN_SIGNATURE)

        parse_artisan_signature(m[2], path, root_url, endpoints, line_no)
      end
    end

    private def parse_artisan_signature(signature : String, path : String, root_url : String,
                                        endpoints : Hash(String, Endpoint), line_no : Int32)
      parts = signature.strip.split(/\s+/, 2)
      name = parts[0]?
      return if name.nil? || name.empty?

      url = "#{root_url}/#{name}"
      endpoint = fetch_endpoint(endpoints, url, path, line_no)
      return if parts.size < 2

      parts[1].scan(ARTISAN_TOKEN) do |tm|
        token = tm[1].strip
        next if token.empty?

        # Strip the ` : description` suffix first — everything downstream
        # (option/default/modifier parsing) must see only the bare token.
        token = token.split(/\s*:\s*/, 2)[0].strip
        next if token.empty?

        is_option = token.starts_with?("--")
        token = token[2..] if is_option
        # `{--Q|queue}` shortcut syntax: keep the long form.
        token = token.split('|').last if token.includes?('|')
        # Strip default value (`name=default`) and optional/array markers.
        token = token.split('=', 2)[0]
        token = token.rstrip("?*")
        token = token.strip
        next if token.empty?

        endpoint.push_param(Param.new(token, "", is_option ? "flag" : "argument"))
      end
    end

    # Robo (`consolidation/robo`) `@command <name>` docblock tag. It binds
    # ONLY to the very next `function` signature encountered — never left
    # sticky across the rest of the file — so an untagged helper method
    # (or a constructor preceding the first tagged command) never inherits
    # another command's params.
    private def scan_robo(lines : Array(String), path : String, root_url : String,
                          endpoints : Hash(String, Endpoint))
      pending_command : String? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        if m = line.match(ROBO_COMMAND_TAG)
          pending_command = m[1]
          next
        end

        next unless cmd = pending_command
        next unless m = line.match(ROBO_FUNCTION_LINE)

        url = "#{root_url}/#{cmd}"
        endpoint = fetch_endpoint(endpoints, url, path, line_no)
        m[1].scan(/\$(\w+)/) do |pm|
          endpoint.push_param(Param.new(pm[1], "", "argument"))
        end
        # Consumed — a later untagged function must not reuse this command.
        pending_command = nil
      end
    end

    # WP-CLI class-command registration. `WP_CLI::add_command('name',
    # 'ClassName')` may appear before OR after the class body
    # (declare-then-register is idiomatic), so registrations and param
    # extraction are collected independently and reconciled at the end.
    # Params are only ever read from the method whose own parameter list
    # is the conventional `($args, $assoc_args)` callback signature —
    # never from unrelated methods elsewhere in the same class.
    private def scan_wp_cli(lines : Array(String), path : String, root_url : String,
                            endpoints : Hash(String, Endpoint))
      registrations = [] of {String, String, Int32}
      class_params = Hash(String, Array(Param)).new

      current_class : String? = nil
      index = 0
      while index < lines.size
        line = lines[index]

        if m = line.match(WP_CLASS_LINE)
          current_class = m[1]
        end

        if (cls = current_class) && line.match(WP_METHOD_LINE)
          body, consumed = extract_brace_body(lines, index)
          params = class_params[cls] ||= [] of Param
          body.each_line do |body_line|
            body_line.scan(WP_ARGS_INDEX) { |am| params << Param.new("arg#{am[1]}", "", "argument") }
            body_line.scan(WP_ASSOC_ARG_BRACKET) { |am| params << Param.new(am[1], "", "flag") }
            body_line.scan(WP_FLAG_VALUE) { |am| params << Param.new(am[1], "", "flag") }
          end
          index += consumed
          next
        end

        if m = line.match(WP_ADD_COMMAND)
          registrations << {m[2], m[3], index + 1}
        end

        index += 1
      end

      registrations.each do |(cmd_name, cls, reg_line_no)|
        params = class_params[cls]?
        next unless params

        url = "#{root_url}/#{cmd_name}"
        endpoint = fetch_endpoint(endpoints, url, path, reg_line_no)
        params.each { |p| endpoint.push_param(p) }
      end
    end

    # Char-level brace matcher starting at `lines[start_index]`. Returns
    # the `{...}` body text (including braces) and the number of lines it
    # spans, so single-line method bodies (`function bar(...) { ... }`,
    # the common WP-CLI style) are handled the same as multi-line ones.
    private def extract_brace_body(lines : Array(String), start_index : Int32) : {String, Int32}
      depth = 0
      started = false
      body = String::Builder.new
      idx = start_index

      while idx < lines.size
        lines[idx].each_char do |ch|
          if ch == '{'
            depth += 1
            started = true
          elsif ch == '}'
            depth -= 1
          end
          body << ch if started
        end
        body << '\n'
        idx += 1
        break if started && depth <= 0
      end

      {body.to_s, idx - start_index}
    end

    private def parse_getopt_short(spec : String, endpoint : Endpoint)
      spec.each_char do |ch|
        next if ch == ':'
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
