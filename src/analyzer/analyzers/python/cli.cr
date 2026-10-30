require "../../../models/analyzer"
require "../../engines/python_engine"
require "../../engines/cli_endpoint_support"

module Analyzer::Python
  # Surfaces the command-line attack surface of Python programs as `cli://`
  # endpoints: one endpoint per (sub)command, with named options
  # (param_type "flag"), positional arguments ("argument"), and consumed
  # environment variables ("env"). Covers stdlib argparse / getopt /
  # sys.argv plus click, typer, fire, docopt, Abseil (absl-py) flags, and
  # Cleo commands.
  #
  # Line-scan analyzer (the house style for non-tree-sitter Python adapters,
  # e.g. bottle). Endpoints are merged by URL so options registered across
  # decorators/functions collect onto a single command.
  class Cli < PythonEngine
    analyzer_for "python_cli"

    include CliEndpointSupport

    # Web frameworks: their os.environ/os.getenv reads are config, not a CLI
    # surface, so raw env is suppressed when one is present (framework-bound
    # env via click/typer is still emitted).
    WEB_FRAMEWORK_RE = /(?:^|\n)\s*(?:import|from)\s+(?:flask|django|fastapi|starlette|sanic|aiohttp|bottle|tornado|falcon|pyramid|quart|litestar|robyn)\b/

    # argparse
    ARGPARSE_NEW_RE     = /(\w+)\s*=\s*(?:argparse\.)?ArgumentParser\s*\(/
    ARGPARSE_PROG_RE    = /ArgumentParser\([^)]*\bprog\s*=\s*[rf]?["']([^"']+)["']/
    ADD_PARSER_RE       = /(\w+)\s*=\s*(\w+)\.add_parser\s*\(\s*[rf]?["']([^"']+)["']/
    ADD_ARGUMENT_RE     = /(\w+)\s*\.\s*add_argument\s*\(([^)]*)/
    ARGPARSE_PARENTS_RE = /\bparents\s*=\s*[\[(]([^\])]*)[\])]/
    ARGPARSE_GROUP_RE   = /(\w+)\s*=\s*(\w+)\s*\.\s*add_(?:argument|mutually_exclusive)_group\s*\(/
    # A parser that is run or carries subcommands is a command even when it
    # is also another parser's parent.
    ARGPARSE_COMMAND_USE_RE = /(\w+)\s*\.\s*(?:add_subparsers|parse_\w*args)\s*\(/
    # `p.add_argument_group("x").add_argument(...)`: receiver and arguments.
    ARGPARSE_INLINE_GROUP_RE = /(\w+)\s*\.\s*add_(?:argument|mutually_exclusive)_group\s*\([^)]*\)\s*\.\s*add_argument\s*\(([^)]*)/
    PY_STRING_LITERAL_RE     = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/

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

    # Abseil (absl-py): flags.DEFINE_* calls register a single flat flag
    # namespace consumed via FLAGS.<name> after app.run(main) — there is no
    # subcommand concept, so every flag attaches to the binary's root URL.
    ABSL_DEFINE_CALL_RE = /\bflags\.DEFINE_(?:string|integer|bool|boolean|float|enum|list|multi_string|multi_integer|multi_enum)\s*\(/
    ABSL_DEFINE_NAME_RE = /\bflags\.DEFINE_(?:string|integer|bool|boolean|float|enum|list|multi_string|multi_integer|multi_enum)\s*\(\s*[rf]?["']([^"']+)["']/

    # Cleo: a Command subclass declares its subcommand name as a class
    # attribute, then reads its own arguments/options back out by name
    # inside its methods (self.argument("x") / self.option("y")) — that
    # readback call is also the most reliable textual anchor for the
    # option/argument name itself.
    CLEO_IMPORT_RE = /(?:^|\n)\s*(?:import\s+cleo\b|from\s+cleo(?:\.\w+)*\s+import\b)/
    # `^` in Crystal/PCRE without the multiline flag anchors to the start of
    # the whole subject, not each line — fine for the per-line `line.match`
    # use in scan_cleo below, but a separate (?:^|\n)-anchored variant is
    # needed to test this against the full multi-line file content. Both
    # variants are column-0 anchored (no `\s*` before `class`) so the
    # entrypoint gate below matches exactly what scan_cleo can extract — a
    # `class Foo(Command)` nested inside a function/method (indented) is
    # never resolved by scan_cleo, so it must not satisfy the gate either,
    # or the file gets treated as a CLI entrypoint with no real command found
    # (scan_stdlib then fires unconditionally on an unrelated env/argv read).
    CLEO_COMMAND_CLASS_RE          = /^class\s+(\w+)\s*\(\s*Command\b/
    CLEO_COMMAND_CLASS_ANYWHERE_RE = /(?:^|\n)class\s+\w+\s*\(\s*Command\b/
    CLEO_NAME_ATTR_RE              = /^\s*name\s*=\s*[rf]?["']([^"']+)["']/
    CLEO_ARGUMENT_CALL_RE          = /\bself\.argument\s*\(\s*[rf]?["']([^"']+)["']/
    CLEO_OPTION_CALL_RE            = /\bself\.option\s*\(\s*[rf]?["']([^"']+)["']/

    def analyze
      python_files = python_source_files
      endpoints = {} of String => Endpoint

      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)

          begin
            content = read_file_content(path)
            next unless cli_entrypoint?(content)

            binary = python_binary_name(content, path)
            root_url = "cli://#{binary}"
            lines = content.lines
            in_string = lines_inside_string(lines)

            scan_argparse(lines, in_string, path, binary, root_url, endpoints)
            scan_click(lines, in_string, path, root_url, endpoints)
            scan_typer(lines, path, root_url, endpoints)
            scan_absl(lines, in_string, path, root_url, endpoints)
            scan_cleo(lines, path, root_url, endpoints)
            scan_stdlib(content, lines, path, root_url, endpoints)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end

      @result.concat(cli_endpoints(endpoints))
      Fiber.yield
      @result
    end

    # The seven literal markers below were seven separate Rabin-Karp
    # passes over the whole file, run for every `.py` in the tree. One
    # precompiled union is the same predicate in a single pass. The
    # remaining tests go through `content_matches?` so PCRE2 skips its
    # per-call UTF-8 revalidation of the buffer. The gate is a pure OR,
    # so collapsing and reordering its terms cannot change the answer.
    CLI_LITERAL_MARKERS_RE = Regex.union(
      "argparse.ArgumentParser", /from\s+argparse\s+import/, "click.command", "click.group",
      "typer.Typer", "fire.Fire", "getopt.getopt", "docopt",
    )

    private def cli_entrypoint?(content : String) : Bool
      return true if content_matches?(content, CLI_LITERAL_MARKERS_RE)
      return true if content_matches?(content, DECORATOR_CMD_RE)
      return true if content_matches?(content, ABSL_DEFINE_CALL_RE)
      return true if content_matches?(content, CLEO_IMPORT_RE) && content_matches?(content, CLEO_COMMAND_CLASS_ANYWHERE_RE)
      content_matches?(content, SYS_ARGV_RE) && content_matches?(content, MAIN_GUARD_RE)
    end

    private def python_binary_name(content : String, path : String) : String
      if m = content.match(ARGPARSE_PROG_RE)
        return m[1]
      end
      stem = File.basename(path, ".py")
      if stem == "__main__" || stem == "__init__"
        if name = cli_directory_binary_name(path)
          return name
        end
      end
      stem
    end

    # argparse: walk the parser calls in source order and attribute each
    # add_argument to the command its receiver was most recently assigned
    # (`p = sub.add_parser(...)` reused for every subcommand is common). A
    # receiver used before any assignment (a helper defined above the
    # builder) falls back to its last assignment in the file. Arguments
    # named in `parents=[...]` are copied onto the parser built from them at
    # that point, as argparse does. A parent that is only a template (never
    # run, no `prog=`, no subcommands of its own) gets no row of its own,
    # unless no recognised parser consumes it: then its arguments stay on
    # the root rather than vanish.
    private def scan_argparse(lines : Array(String), in_string : Array(Bool), path : String,
                              binary : String, root_url : String, endpoints : Hash(String, Endpoint))
      # Join each multi-line call (the Black/PEP8 shape puts the name of an
      # `add_argument(` / `add_parser(` on its own following line) so the
      # name token is visible on one logical line. The join is string- and
      # comment-aware, so a `(` in a help text doesn't swallow the lines
      # after it.
      calls = [] of Tuple(Int32, String)
      commands = Set(String).new
      index = 0
      while index < lines.size
        line = lines[index]
        if in_string[index]
          index += 1
          next
        end
        if line.includes?("pars")
          _, _, comment = python_call_line_scan(line, nil)
          code = line.byte_slice(0, comment).gsub(PY_STRING_LITERAL_RE, "\"\"")
          code.scan(ARGPARSE_COMMAND_USE_RE) { |m| commands << m[1] }
        end
        if line.lstrip.starts_with?('#') ||
           !(line.includes?("add_argument") || line.includes?("add_parser") ||
           line.includes?("ArgumentParser") || line.includes?("_group"))
          index += 1
          next
        end
        logical, last = python_call_span(lines, index, line)
        calls << {index + 1, logical}
        index = last + 1
      end
      return if calls.empty?

      templates = Set(String).new
      calls.each do |_, call|
        next unless m = call.match(ARGPARSE_NEW_RE)
        commands << m[1] if call.matches?(ARGPARSE_PROG_RE)
      end
      calls.each do |_, call|
        next unless argparse_parser_target(call, root_url)
        argparse_parents(call).each { |name| templates << name unless commands.includes?(name) }
      end

      last_urls = {} of String => String
      calls.each do |_, call|
        if (target = argparse_parser_target(call, root_url)) && !templates.includes?(target[0])
          last_urls[target[0]] = target[1]
        end
      end
      return if last_urls.empty?

      # Each assignment builds a new parser: {command URL (nil for a
      # template), its arguments so far}. Variables and argument groups point
      # at the parser they held when assigned, so reusing a variable for the
      # next subcommand leaves an earlier group on the earlier one.
      parsers = [] of Tuple(String?, Array(Param))
      var_parser = {} of String => Int32
      calls.each do |line_no, call|
        if target = argparse_parser_target(call, root_url)
          var, url = target
          inherited = argparse_parents(call).flat_map { |name| var_parser[name]?.try { |id| parsers[id][1] } || [] of Param }
          url = nil if templates.includes?(var)
          var_parser[var] = parsers.size
          parsers << {url, inherited.dup}
          if url && !inherited.empty?
            ep = fetch_endpoint(endpoints, url, path, line_no)
            inherited.each { |param| ep.push_param(param) }
          end
        elsif m = call.match(ARGPARSE_GROUP_RE)
          # An argument group adds to the parser it was made from.
          owner = m[2]
          var_parser[m[1]] = var_parser[owner]? || (parsers << {templates.includes?(owner) ? nil : last_urls[owner]?, [] of Param}).size - 1
          next
        end

        next unless m = call.match(ADD_ARGUMENT_RE) || call.match(ARGPARSE_INLINE_GROUP_RE)
        # The canonical form declares both names — `add_argument("-v",
        # "--verbose")` — and argparse derives the destination from the long
        # one, so prefer it over the short alias. Cut at the first `=` so
        # keyword-argument values (help=, metavar=, dest=) can't pose as
        # name tokens.
        tokens = [] of String
        m[2].split('=').first.scan(/[rf]?["']([^"']+)["']/) { |t| tokens << t[1] }
        next unless first = tokens.first?
        param = if first.starts_with?("-")
                  Param.new((tokens.find(&.starts_with?("--")) || first).lstrip('-'), "", "flag")
                else
                  Param.new(first, "", "argument")
                end

        receiver = m[1]
        if id = var_parser[receiver]?
          url, params = parsers[id]
          params << param
        else
          url = templates.includes?(receiver) ? nil : last_urls[receiver]?
        end
        fetch_endpoint(endpoints, url, path, line_no).push_param(param) if url
      end
    end

    # `{variable, command URL}` for a `x = ArgumentParser(...)` or
    # `x = sub.add_parser("name", ...)` assignment.
    private def argparse_parser_target(call : String, root_url : String) : Tuple(String, String)?
      if m = call.match(ADD_PARSER_RE)
        {m[1], "#{root_url}/#{m[3]}"}
      elsif m = call.match(ARGPARSE_NEW_RE)
        {m[1], root_url}
      end
    end

    # Plain variable names in a `parents=[a, b]` keyword; a call or an
    # attribute (`parents=[tools.argparser]`) is not a local template.
    private def argparse_parents(call : String) : Array(String)
      names = [] of String
      return names unless call.includes?("parents")
      if m = call.match(ARGPARSE_PARENTS_RE)
        m[1].split(',') do |item|
          item = item.strip
          names << item if item.matches?(/\A\w+\z/)
        end
      end
      names
    end

    # click: stacked decorators sit above the handler `def`. Buffer the
    # @option/@argument decorators, then flush them onto the command endpoint
    # when the def is reached. A top-level @click.group() is the binary root.
    private def scan_click(lines : Array(String), in_string : Array(Bool), path : String,
                           root_url : String, endpoints : Hash(String, Endpoint))
      pending_params = [] of Param
      pending_cmd : NamedTuple(receiver: String, kind: String, name: String?)? = nil
      pending_line = 0

      index = 0
      while index < lines.size
        stripped = lines[index].strip

        # A docstring line is text, not a decorator or def.
        if in_string[index]
          index += 1
          next
        end

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
          logical, index = python_call_span(lines, index, stripped)
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

    # Whether each line starts inside a triple-quoted string (a docstring
    # body), where a `(` is text and must not start a call join.
    private def lines_inside_string(lines : Array(String)) : Array(Bool)
      triple : Char? = nil
      lines.map do |line|
        inside = !triple.nil?
        _, triple, _ = python_call_line_scan(line, triple)
        inside
      end
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

    # absl-py: flags.DEFINE_* has no receiver/scope to attribute — every
    # declared flag is a global, consumed via FLAGS.<name> anywhere in the
    # program — so every match simply attaches to the binary's root URL.
    # Joins a multi-line call (the name may land on its own continuation
    # line) the same way scan_argparse joins add_argument.
    private def scan_absl(lines : Array(String), in_string : Array(Bool), path : String,
                          root_url : String, endpoints : Hash(String, Endpoint))
      index = 0
      while index < lines.size
        line = lines[index]
        if in_string[index] || !line.matches?(ABSL_DEFINE_CALL_RE)
          index += 1
          next
        end
        start = index
        logical, index = python_call_span(lines, index, line)
        if m = logical.match(ABSL_DEFINE_NAME_RE)
          fetch_endpoint(endpoints, root_url, path, start + 1).push_param(Param.new(m[1], "", "flag"))
        end
        index += 1
      end
    end

    # Cleo: each `class FooCommand(Command):` is a subcommand keyed by its
    # `name = "..."` class attribute. Scope every self.argument()/
    # self.option() readback found anywhere in the class body (covers
    # handle() and any helper methods) to that command's URL — never a
    # sticky cursor, so a second command class can't inherit stray params.
    private def scan_cleo(lines : Array(String), path : String, root_url : String,
                          endpoints : Hash(String, Endpoint))
      index = 0
      while index < lines.size
        line = lines[index]
        unless line.matches?(CLEO_COMMAND_CLASS_RE)
          index += 1
          next
        end
        class_indent = line.size - line.lstrip.size
        body_start = index + 1
        body_end = body_start
        while body_end < lines.size
          candidate = lines[body_end]
          stripped = candidate.strip
          if stripped.empty? || stripped.starts_with?("#")
            body_end += 1
            next
          end
          break if candidate.size - candidate.lstrip.size <= class_indent
          body_end += 1
        end

        # Only the class's direct-member indentation (the indentation of its
        # first non-blank/non-comment body line) counts as a class attribute.
        # A `name = "..."` local variable inside a nested method body sits
        # deeper than that and must not hijack the command's URL.
        name = nil
        member_indent = nil
        (body_start...body_end).each do |i|
          body_line = lines[i]
          stripped = body_line.strip
          next if stripped.empty? || stripped.starts_with?("#")
          indent = body_line.size - body_line.lstrip.size
          member_indent ||= indent
          next unless indent == member_indent
          if nm = body_line.match(CLEO_NAME_ATTR_RE)
            name = nm[1]
            break
          end
        end

        if name
          url = "#{root_url}/#{name}"
          ep = fetch_endpoint(endpoints, url, path, body_start + 1)
          (body_start...body_end).each do |i|
            body_line = lines[i]
            body_line.scan(CLEO_ARGUMENT_CALL_RE) { |am| ep.push_param(Param.new(am[1], "", "argument")) }
            body_line.scan(CLEO_OPTION_CALL_RE) { |om| ep.push_param(Param.new(om[1], "", "flag")) }
          end
        end

        index = body_end
      end
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
  end
end
