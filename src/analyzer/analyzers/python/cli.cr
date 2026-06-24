require "../../../models/analyzer"
require "../../engines/python_engine"

module Analyzer::Python
  # Surfaces the command-line attack surface of Python programs as `cli://`
  # endpoints: one endpoint per (sub)command, with named options
  # (param_type "flag"), positional arguments ("argument"), and consumed
  # environment variables ("env"). Covers stdlib argparse / getopt /
  # sys.argv plus click, typer, fire and docopt.
  #
  # Line-scan analyzer (the house style for non-tree-sitter Python adapters,
  # e.g. bottle). Endpoints are merged by URL so options registered across
  # decorators/functions collect onto a single command.
  class Cli < PythonEngine
    # Web frameworks: their os.environ/os.getenv reads are config, not a CLI
    # surface, so raw env is suppressed when one is present (framework-bound
    # env via click/typer is still emitted).
    WEB_FRAMEWORK_RE = /(?:^|\n)\s*(?:import|from)\s+(?:flask|django|fastapi|starlette|sanic|aiohttp|bottle|tornado|falcon|pyramid|quart|litestar|robyn)\b/

    # argparse
    ARGPARSE_NEW_RE  = /(\w+)\s*=\s*argparse\.ArgumentParser\s*\(/
    ARGPARSE_PROG_RE = /ArgumentParser\([^)]*\bprog\s*=\s*[rf]?["']([^"']+)["']/
    ADD_PARSER_RE    = /(\w+)\s*=\s*(\w+)\.add_parser\s*\(\s*[rf]?["']([^"']+)["']/
    ADD_ARGUMENT_RE  = /(\w+)\s*\.\s*add_argument\s*\(\s*[rf]?["']([^"']+)["']/

    # click / typer decorators
    DECORATOR_CMD_RE  = /^@(\w+)\.(command|group|callback)\s*\(/
    DECORATOR_NAME_RE = /\(\s*[rf]?["']([^"']+)["']/
    CLICK_OPTION_RE   = /^@\w+\.option\s*\(/
    CLICK_ARGUMENT_RE = /^@\w+\.argument\s*\(/
    ENVVAR_RE         = /\benvvar\s*=\s*[rf]?["']([^"']+)["']/
    DEF_RE            = /^def\s+(\w+)\s*\(/

    # typer
    TYPER_NEW_RE            = /(\w+)\s*=\s*typer\.Typer\s*\(/
    TYPER_OPTION_PARAM_RE   = /(\w+)\s*:[^,=]+=\s*typer\.Option/
    TYPER_ARGUMENT_PARAM_RE = /(\w+)\s*:[^,=]+=\s*typer\.Argument/

    # stdlib argv / env / getopt
    SYS_ARGV_RE       = /\bsys\.argv\s*\[\s*(\d+)\s*\]/
    MAIN_GUARD_RE     = /if\s+__name__\s*==\s*[rf]?["']__main__["']/
    OS_ENVIRON_RE     = /\bos\.environ\s*\[\s*[rf]?["']([^"']+)["']\s*\]/
    OS_ENVIRON_GET_RE = /\bos\.environ\.get\s*\(\s*[rf]?["']([^"']+)["']/
    OS_GETENV_RE      = /\bos\.getenv\s*\(\s*[rf]?["']([^"']+)["']/
    GETOPT_RE         = /getopt\.getopt\s*\([^,]+,\s*[rf]?["']([^"']*)["']\s*(?:,\s*\[([^\]]*)\])?/
    FIRE_RE           = /\bfire\.Fire\s*\(\s*(\w+)/

    def analyze
      python_files = get_files_by_extension(".py")
      endpoints = {} of String => Endpoint

      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)

          begin
            content = read_file_content(path)
            next unless cli_entrypoint?(content)

            binary = python_binary_name(content, path)
            root_url = "cli://#{binary}"
            lines = content.lines

            scan_argparse(lines, path, binary, root_url, endpoints)
            scan_click(lines, path, root_url, endpoints)
            scan_typer(lines, path, root_url, endpoints)
            scan_stdlib(content, lines, path, root_url, endpoints)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end

      endpoints.each_value { |ep| @result << ep }
      Fiber.yield
      @result
    end

    private def cli_entrypoint?(content : String) : Bool
      return true if content.includes?("argparse.ArgumentParser")
      return true if content.matches?(DECORATOR_CMD_RE) || content.includes?("click.command") ||
                     content.includes?("click.group")
      return true if content.includes?("typer.Typer")
      return true if content.includes?("fire.Fire")
      return true if content.includes?("getopt.getopt")
      return true if content.includes?("docopt")
      content.matches?(SYS_ARGV_RE) && content.matches?(MAIN_GUARD_RE)
    end

    private def python_binary_name(content : String, path : String) : String
      if m = content.match(ARGPARSE_PROG_RE)
        return m[1]
      end
      stem = File.basename(path, ".py")
      if stem == "__main__" || stem == "__init__"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    # argparse: map each parser variable to its command URL, then attribute
    # every add_argument by its receiver variable (robust against ordering).
    private def scan_argparse(lines : Array(String), path : String, binary : String,
                              root_url : String, endpoints : Hash(String, Endpoint))
      var_urls = {} of String => String
      lines.each do |line|
        if m = line.match(ARGPARSE_NEW_RE)
          var_urls[m[1]] = root_url
        end
        if m = line.match(ADD_PARSER_RE)
          var_urls[m[1]] = "#{root_url}/#{m[3]}"
        end
      end
      return if var_urls.empty?

      lines.each_with_index do |line, index|
        next unless m = line.match(ADD_ARGUMENT_RE)
        url = var_urls[m[1]]?
        next unless url
        ep = fetch_endpoint(endpoints, url, path, index + 1)
        token = m[2]
        if token.starts_with?("-")
          ep.push_param(Param.new(token.lstrip('-'), "", "flag"))
        else
          ep.push_param(Param.new(token, "", "argument"))
        end
      end
    end

    # click: stacked decorators sit above the handler `def`. Buffer the
    # @option/@argument decorators, then flush them onto the command endpoint
    # when the def is reached. A top-level @click.group() is the binary root.
    private def scan_click(lines : Array(String), path : String, root_url : String,
                           endpoints : Hash(String, Endpoint))
      pending_params = [] of Param
      pending_cmd : NamedTuple(receiver: String, kind: String, name: String?)? = nil
      pending_line = 0

      index = 0
      while index < lines.size
        stripped = lines[index].strip

        # Blank lines and comments don't break a decorator stack (Black often
        # leaves a comment between the decorators and the def).
        if stripped.empty? || stripped.starts_with?("#")
          index += 1
          next
        end

        # Join decorators/defs that span multiple physical lines (the standard
        # Black/PEP8 shape) so every argument is visible on one logical line
        # and the continuation lines aren't mistaken for stack-breaking
        # statements.
        start_line = index
        logical = stripped
        if stripped.starts_with?("@") || stripped.starts_with?("def ")
          while parens_unbalanced?(logical) && index + 1 < lines.size
            index += 1
            logical += " " + lines[index].strip
          end
        end

        if m = logical.match(DECORATOR_CMD_RE)
          name = logical.match(DECORATOR_NAME_RE).try(&.[1])
          pending_cmd = {receiver: m[1], kind: m[2], name: name}
          pending_line = start_line + 1
        elsif logical.matches?(CLICK_OPTION_RE)
          if opt = click_option_name(logical)
            pending_params << Param.new(opt, "", "flag")
          end
          if env = logical.match(ENVVAR_RE)
            pending_params << Param.new(env[1], "", "env")
          end
        elsif logical.matches?(CLICK_ARGUMENT_RE)
          if arg = logical.match(DECORATOR_NAME_RE)
            pending_params << Param.new(arg[1], "", "argument")
          end
        elsif (cmd = pending_cmd) && (dm = logical.match(DEF_RE))
          name = cmd[:name] || dm[1].gsub('_', '-')
          # A top-level group is the binary itself; everything else is a
          # subcommand under the root (flattened in v1).
          url = if cmd[:kind] == "group" && cmd[:receiver] == "click"
                  root_url
                else
                  "#{root_url}/#{name}"
                end
          ep = fetch_endpoint(endpoints, url, path, pending_line)
          pending_params.each { |p| ep.push_param(p) }
          pending_cmd = nil
          pending_params.clear
        elsif pending_cmd && !logical.starts_with?("@")
          # A real statement (not a decorator/def/comment) broke the stack.
          pending_cmd = nil
          pending_params.clear
        end

        index += 1
      end
    end

    # Whether `text` has more `(` than `)` — used to detect a decorator/def
    # whose argument list continues on the next physical line.
    private def parens_unbalanced?(text : String) : Bool
      depth = 0
      text.each_char do |ch|
        depth += 1 if ch == '('
        depth -= 1 if ch == ')'
      end
      depth > 0
    end

    # Picks the long option (`--name`) when present, else the short one.
    private def click_option_name(decorator : String) : String?
      long = nil
      short = nil
      decorator.scan(/[rf]?["'](-{1,2}[A-Za-z0-9][\w-]*)["']/) do |m|
        token = m[1]
        if token.starts_with?("--")
          long ||= token.lstrip('-')
        else
          short ||= token.lstrip('-')
        end
      end
      long || short
    end

    # typer: @app.command() above a def whose typed parameters carry
    # typer.Option / typer.Argument defaults.
    private def scan_typer(lines : Array(String), path : String, root_url : String,
                           endpoints : Hash(String, Endpoint))
      typer_vars = Set(String).new
      lines.each do |line|
        if m = line.match(TYPER_NEW_RE)
          typer_vars << m[1]
        end
      end
      return if typer_vars.empty?

      pending : NamedTuple(name: String?, line: Int32)? = nil
      lines.each_with_index do |line, index|
        stripped = line.strip
        if m = stripped.match(DECORATOR_CMD_RE)
          next unless typer_vars.includes?(m[1]) && m[2] == "command"
          pending = {name: stripped.match(DECORATOR_NAME_RE).try(&.[1]), line: index + 1}
          next
        end
        next unless cmd = pending
        next unless dm = stripped.match(DEF_RE)

        name = cmd[:name] || dm[1].gsub('_', '-')
        url = "#{root_url}/#{name}"
        ep = fetch_endpoint(endpoints, url, path, cmd[:line])

        # Collect the parameter section (def may span several lines) and pull
        # typer.Option/Argument params + their envvar bindings out of it.
        signature = collect_signature(lines, index)
        signature.each_line do |sig_line|
          if pm = sig_line.match(TYPER_OPTION_PARAM_RE)
            ep.push_param(Param.new(pm[1], "", "flag"))
          end
          if pm = sig_line.match(TYPER_ARGUMENT_PARAM_RE)
            ep.push_param(Param.new(pm[1], "", "argument"))
          end
          if env = sig_line.match(ENVVAR_RE)
            ep.push_param(Param.new(env[1], "", "env"))
          end
        end
        pending = nil
      end
    end

    # Accumulates a function signature from its `def` line until the closing
    # `):` (inclusive), so multi-line typer signatures parse fully.
    private def collect_signature(lines : Array(String), def_index : Int32) : String
      buffer = String::Builder.new
      index = def_index
      while index < lines.size
        line = lines[index]
        buffer << line << '\n'
        break if line.includes?("):") || line.matches?(/\)\s*->/)
        index += 1
        break if index - def_index > 80 # safety bound
      end
      buffer.to_s
    end

    # stdlib: raw env reads (gated), sys.argv positionals, getopt, fire.
    private def scan_stdlib(content : String, lines : Array(String), path : String,
                            root_url : String, endpoints : Hash(String, Endpoint))
      emit_env = !content.matches?(WEB_FRAMEWORK_RE)
      has_main = content.matches?(MAIN_GUARD_RE)

      lines.each_with_index do |line, index|
        line_no = index + 1
        if emit_env
          {OS_ENVIRON_RE, OS_ENVIRON_GET_RE, OS_GETENV_RE}.each do |re|
            # `scan` so multiple env reads on one line all surface.
            line.scan(re) do |m|
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "env"))
            end
          end
        end
        if has_main && (m = line.match(SYS_ARGV_RE)) && m[1] != "0"
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
        end
      end

      # getopt short/long option specs.
      if m = content.match(GETOPT_RE)
        ep = fetch_endpoint(endpoints, root_url, path, 1)
        parse_getopt_short(m[1], ep)
        if longs = m[2]?
          longs.scan(/[rf]?["']([^"']+)["']/) do |lm|
            ep.push_param(Param.new(lm[1].rstrip('='), "", "flag"))
          end
        end
      end

      # fire exposes a class/function's methods as subcommands; best-effort
      # marker only (method enumeration is a follow-up).
      if m = content.match(FIRE_RE)
        fetch_endpoint(endpoints, root_url, path, 1)
        logger.debug "fire.Fire(#{m[1]}) detected in #{path}; method enumeration not yet implemented"
      end
    end

    # getopt short spec like "hf:o:" -> flags h, f, o.
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
