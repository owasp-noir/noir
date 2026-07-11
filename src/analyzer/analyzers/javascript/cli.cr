require "../../../models/analyzer"
require "../../engines/javascript_engine"

module Analyzer::Javascript
  # Surfaces the command-line attack surface of JavaScript/TypeScript programs
  # (Node, Deno, Bun) as `cli://` endpoints: one endpoint per (sub)command
  # with named options (param_type "flag"), positional arguments ("argument")
  # and consumed environment variables ("env"). Covers the `util.parseArgs`
  # builtin plus commander, yargs, cac, sade, meow, minimist, arg,
  # command-line-args, getopts and citty. A single analyzer scans every JS/TS
  # extension so a `.ts` CLI isn't double-counted.
  class Cli < JavascriptEngine
    SOURCE_EXTS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".cts", ".tsx"]

    # commander / cac / sade / yargs subcommand. The command string may carry
    # an arg spec (`serve <port>`), so the first whitespace token is the name.
    COMMAND_RE = /\.\s*command\s*\(\s*['"]([^'"]+)['"]/
    # commander/cac/sade: `.option('-p, --port <n>')`; yargs: `.option('port')`.
    OPTION_RE     = /\.\s*(?:required)?[Oo]ption\s*\(\s*['"]([^'"]+)['"]/
    ARGUMENT_RE   = /\.\s*argument\s*\(\s*['"][<\[]?\.{0,3}([A-Za-z0-9_-]+)/
    POSITIONAL_RE = /\.\s*positional\s*\(\s*['"]([^'"]+)['"]/
    LONG_FLAG_RE  = /(--[A-Za-z0-9][\w-]*)/
    SHORT_FLAG_RE = /(-[A-Za-z0-9])\b/

    # builtin / runtime argv markers (root surface).
    DENO_ARGS  = /\bDeno\.args\b/
    BUN_ARGV   = /\bBun\.argv\b/
    ARGV_SLICE = /\bprocess\.argv\.slice\s*\(\s*2\s*\)/

    # object-literal schema headers (keys become root flags).
    PARSEARGS_HEADER  = /\boptions\s*:\s*\{/
    MEOW_FLAGS_HEADER = /\bflags\s*:\s*\{/
    OBJECT_KEY_RE     = /^\s*['"]?([A-Za-z_$][\w$-]*)['"]?\s*:/

    # arg: `arg({ '--name': String, '-n': '--name' })`. Keys whose value is a
    # quoted string are aliases pointing at the canonical flag and are
    # skipped so an alias doesn't surface as a second, meaningless flag.
    ARG_CALL_RE = /\barg\s*\(\s*\{/
    ARG_KEY_RE  = /^\s*['"](-{1,2}[A-Za-z][\w-]*)['"]\s*:\s*(.+?),?\s*$/

    # command-line-args: `commandLineArgs(optionDefinitions)` referencing a
    # separately-declared `const optionDefinitions = [...]` array (the
    # library's own documented convention), or an inline
    # `commandLineArgs([...])` array. Matching is bounded to the resolved
    # array's own brackets (never a whole-file scan) so an unrelated
    # same-shaped object literal elsewhere in the file (e.g. a content-field
    # schema) is never picked up as a bogus flag, and each `{...}` entry is
    # scanned as its own brace-bounded block so Prettier-style
    # multi-line-per-key formatting isn't silently dropped.
    CLA_ARRAY_ASSIGN_RE = /^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*\[/
    CLA_CALL_VAR_RE     = /\bcommandLineArgs\s*\(\s*([A-Za-z_$][\w$]*)\s*[,)]/
    CLA_CALL_INLINE_RE  = /\bcommandLineArgs\s*\(\s*\[/
    CLA_NAME_RE         = /\bname\s*:\s*['"]([A-Za-z0-9_-]+)['"]/
    CLA_TYPE_KEY_RE     = /\btype\s*:/

    # getopts: `getopts(process.argv.slice(2), { alias: {...}, default: {...},
    # boolean: [...], string: [...] })`. Bounded to the call's own parens so
    # unrelated `alias`/`default` object literals elsewhere aren't picked up.
    GETOPTS_CALL_RE        = /\bgetopts\s*\(/
    GETOPTS_ALIAS_HEADER   = /\balias\s*:\s*\{/
    GETOPTS_DEFAULT_HEADER = /\bdefault\s*:\s*\{/
    GETOPTS_BOOLEAN_HEADER = /\bboolean\s*:\s*\[/
    GETOPTS_STRING_HEADER  = /\bstring\s*:\s*\[/
    OBJECT_VALUE_RE        = /^\s*['"]?[A-Za-z_$][\w$-]*['"]?\s*:\s*['"]([A-Za-z0-9_-]+)['"]/
    STRING_LIT_RE          = /['"]([A-Za-z0-9_.\/-]+)['"]/

    # citty: `serve: defineCommand({ args: { port: { type: 'string' } } })`.
    # Subcommands nest their own `defineCommand` object inside `subCommands`,
    # so args are attributed via a brace-depth stack (never a sticky cursor).
    CITTY_SUBCOMMAND_RE = /^\s*['"]?([A-Za-z_$][\w$-]*)['"]?\s*:\s*defineCommand\s*\(\s*\{/
    CITTY_ARGS_HEADER   = /\bargs\s*:\s*\{/

    # citty also allows each subcommand to be declared as its own top-level
    # `const NAME = defineCommand({...})` and merely referenced by identifier
    # inside `subCommands: { key: NAME }`, instead of nesting the
    # `defineCommand` call inline. `resolve_citty_var_subcommands` resolves
    # those same-file references so `args:` inside NAME's block attributes to
    # `<root>/<key>` rather than falling back to root.
    CITTY_DEFINE_ASSIGN_RE   = /^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*defineCommand\s*\(\s*\{/
    CITTY_SUBCOMMANDS_HEADER = /\bsubCommands\s*:\s*\{/
    CITTY_SUBCOMMAND_REF_RE  = /^\s*['"]?([A-Za-z_$][\w$-]*)['"]?\s*:\s*([A-Za-z_$][\w$]*)\s*,?\s*$/

    # `require('arg')` / `from 'arg'`, and likewise for getopts/citty/
    # command-line-args — these are short/generic tokens too easy to trip as
    # a bare substring (e.g. bash's own `getopts` builtin, a stray comment,
    # or an ordinary identifier fragment), so they require an actual import
    # statement rather than `content.includes?`.
    LIB_IMPORT_ONLY_RE = /(?:require\s*\(\s*|from\s+)['"](?:arg|getopts|citty|command-line-args)['"]/

    # A fresh statement that chains command/option/argument off an identifier
    # (`program.option(...)`, `cli.command(...)`) starts at the root program,
    # not the previously-seen subcommand — used to reset the cursor so a
    # global option declared after a subcommand isn't mis-attributed to it.
    NEW_CHAIN_RE = /^[A-Za-z_$][\w$]*\s*\.\s*(?:command|option|argument)\b/

    # env reads (gated). NODE_ENV is config plumbing, not an input.
    ENV_DOT   = /\bprocess\.env\.([A-Za-z_][A-Za-z0-9_]*)/
    ENV_INDEX = /\bprocess\.env\s*\[\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*\]/
    DENO_ENV  = /\bDeno\.env\.get\s*\(\s*['"]([^'"]+)['"]/
    BUN_ENV   = /\bBun\.env\.([A-Za-z_][A-Za-z0-9_]*)/

    WEB_FRAMEWORK_RE = /(?:require\s*\(\s*|from\s+)['"](?:express|fastify|koa|@hapi\/hapi|@nestjs\/[\w-]+|next|nuxt|hono|@hono\/[\w-]+|restify|@adonisjs\/[\w-]+|elysia|polka|connect|h3|@sveltejs\/[\w-]+|@remix-run\/[\w-]+|apollo-server|@apollo\/server)['"]/
    WEB_LISTEN_RE    = /\.\s*listen\s*\(|\bcreateServer\s*\(/

    CLI_MARKERS = ["commander", "yargs", "cac", "meow", "minimist", "clipanion", "@oclif", "sade", "parseArgs", "Deno.args", "Bun.argv"]

    def analyze
      package_names = collect_package_names
      endpoints = {} of String => Endpoint

      base_paths.each do |current_base_path|
        SOURCE_EXTS.each do |ext|
          get_files_by_extension(ext).each do |path|
            next unless path_under_root?(path, current_base_path)
            next if js_test_or_vendor?(path)

            begin
              content = read_file_content(path)
              next unless cli_evidence?(content)

              binary = js_binary_name(package_names, path)
              root_url = "cli://#{binary}"
              lines = content.lines
              emit_env = !(content.matches?(WEB_FRAMEWORK_RE) || content.matches?(WEB_LISTEN_RE))

              scan(lines, path, root_url, endpoints, emit_env)
            rescue e
              logger.debug "Error analyzing #{path}: #{e}"
              next
            end
          end
        end
      end

      endpoints.each_value { |ep| @result << ep }
      Fiber.yield
      @result
    end

    private def cli_evidence?(content : String) : Bool
      CLI_MARKERS.any? { |m| content.includes?(m) } || content.matches?(ARGV_SLICE) ||
        content.matches?(LIB_IMPORT_ONLY_RE)
    end

    private def js_test_or_vendor?(path : String) : Bool
      path.includes?("/node_modules/") || path.includes?("/__tests__/") ||
        path.includes?(".test.") || path.includes?(".spec.") || path.includes?(".d.ts")
    end

    private def scan(lines : Array(String), path : String, root_url : String,
                     endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url

      # citty subcommand context: a stack of (url, brace-depth-at-which-this
      # subcommand's own `defineCommand({` opened). Args attach to the
      # innermost context still open at the current depth, never to a sticky
      # last-seen command.
      citty_stack = [] of Tuple(String, Int32)
      brace_depth = 0

      # citty subcommands declared as a separate `const NAME = defineCommand`
      # and referenced by identifier from `subCommands: { key: NAME }` (see
      # CITTY_DEFINE_ASSIGN_RE) — resolved once up front from the whole file
      # since the reference can precede or follow the declaration.
      var_subcommand_ranges = resolve_citty_var_subcommands(lines, root_url)
      var_subcommand_ranges.each { |(s, _e, u)| fetch_endpoint(endpoints, u, path, s + 1) }

      # command-line-args option-definition arrays declared separately from
      # the `commandLineArgs(...)` call and referenced by identifier — built
      # forward as `const NAME = [...]` assignments are seen, so a lookup at
      # the call site only ever resolves an array already declared earlier in
      # the same file (never a later reassignment silently taking over).
      cla_array_bounds = {} of String => Tuple(Int32, Int32)

      index = 0
      while index < lines.size
        line = lines[index]
        line_no = index + 1

        # A new statement chaining off the root program var resets the cursor
        # to root before this line's .command (if any) re-sets it, so a global
        # `program.option(...)` after a subcommand attributes to the root.
        current_url = root_url if line.lstrip.matches?(NEW_CHAIN_RE)

        # Subcommand: set the cursor so subsequent option/argument lines (and
        # ones chained on the same line) attribute to it.
        if m = line.match(COMMAND_RE)
          token = m[1].strip.split(/\s+/).first? || ""
          # yargs' `$0`/`*` and an empty token denote the default (root) command.
          if token.empty? || token == "$0" || token == "*"
            current_url = root_url
          else
            current_url = "#{root_url}/#{token}"
            fetch_endpoint(endpoints, current_url, path, line_no)
          end
        end

        if m = line.match(OPTION_RE)
          name = option_name(m[1])
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(name, "", "flag")) unless name.empty?
        end
        if m = line.match(ARGUMENT_RE)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end
        if m = line.match(POSITIONAL_RE)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end

        # Object-schema option blocks (util.parseArgs, meow) -> root flags.
        if line.matches?(PARSEARGS_HEADER) || line.matches?(MEOW_FLAGS_HEADER)
          collect_object_keys(lines, index).each do |key|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(key, "", "flag"))
          end
        end

        # arg: `arg({ '--name': String, '-n': '--name' })` -> root flags.
        if line.matches?(ARG_CALL_RE)
          arg_flags(lines, index).each do |flag_name|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(flag_name, "", "flag"))
          end
        end

        # command-line-args: track `const NAME = [...]` array declarations so
        # a later `commandLineArgs(NAME)` reference can be resolved to the
        # exact array it passes (never a whole-file regex scan).
        if m = line.match(CLA_ARRAY_ASSIGN_RE)
          cla_array_bounds[m[1]] = {index, brace_bounded_end(lines, index, '[', ']')}
        end

        # command-line-args: `commandLineArgs([{ name: 'x', type: Boolean }])`
        # (inline array) or `commandLineArgs(optionDefinitions)` (reference to
        # an array declared earlier in this file, per the library's own
        # documented convention).
        if line.matches?(CLA_CALL_INLINE_RE)
          arr_end = brace_bounded_end(lines, index, '[', ']')
          cla_option_entries(lines, index, arr_end).each do |(name, ptype)|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", ptype))
          end
        elsif m = line.match(CLA_CALL_VAR_RE)
          if bounds = cla_array_bounds[m[1]]?
            cla_option_entries(lines, bounds[0], bounds[1]).each do |(name, ptype)|
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", ptype))
            end
          end
        end

        # getopts: `getopts(argv, { alias, default, boolean, string })`.
        if line.matches?(GETOPTS_CALL_RE)
          block_end = brace_bounded_end(lines, index, '(', ')')
          getopts_flags(lines, index, block_end).each do |opt_name|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(opt_name, "", "flag"))
          end
        end

        # citty: `name: defineCommand({ ... })` opens a subcommand context;
        # args attach to the innermost open context (root when the stack is
        # empty), scoped by brace depth rather than a sticky cursor.
        pending_citty_url = nil
        if m = line.match(CITTY_SUBCOMMAND_RE)
          sub_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, sub_url, path, line_no)
          pending_citty_url = sub_url
        end
        if line.matches?(CITTY_ARGS_HEADER)
          ctx_url = citty_stack.last?.try(&.[0])
          ctx_url ||= var_subcommand_ranges.find { |(s, e, _u)| index >= s && index <= e }.try(&.[2])
          ctx_url ||= root_url
          collect_object_keys(lines, index).each do |key|
            fetch_endpoint(endpoints, ctx_url, path, line_no).push_param(Param.new(key, "", "flag"))
          end
        end

        # Runtime argv markers -> ensure a root endpoint exists.
        if line.matches?(DENO_ARGS) || line.matches?(BUN_ARGV) || line.matches?(ARGV_SLICE)
          fetch_endpoint(endpoints, root_url, path, line_no)
        end

        if emit_env
          {ENV_DOT, ENV_INDEX, DENO_ENV, BUN_ENV}.each do |re|
            line.scan(re) do |env_match|
              name = env_match[1]
              next if name == "NODE_ENV"
              fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "env"))
            end
          end
        end

        line.each_char do |ch|
          if ch == '{'
            brace_depth += 1
          elsif ch == '}'
            brace_depth -= 1
            while (top = citty_stack.last?) && brace_depth < top[1]
              citty_stack.pop
            end
          end
        end
        if pending_citty_url
          citty_stack.push({pending_citty_url, brace_depth})
        end

        index += 1
      end
    end

    # commander/cac/sade flag strings carry dashes (`-p, --port <n>`); yargs
    # passes the bare long name. Prefer the `--long`, then `-short`, else the
    # string as-is (yargs).
    private def option_name(raw : String) : String
      if m = raw.match(LONG_FLAG_RE)
        return m[1].lstrip('-')
      end
      if m = raw.match(SHORT_FLAG_RE)
        return m[1].lstrip('-')
      end
      raw.includes?(' ') ? "" : raw
    end

    # Collects the top-level keys of the object literal that opens on/after
    # `start`, bounded by its braces.
    private def collect_object_keys(lines : Array(String), start : Int32) : Array(String)
      keys = [] of String
      depth = 0
      seen_open = false
      index = start
      while index < lines.size
        line = lines[index]
        # depth == 1 is the flag-name level of the schema; option descriptor
        # keys (type/alias/default) live one level deeper and are never seen
        # here, so every key collected is a real flag name (including one
        # literally named `type`).
        if seen_open && depth == 1 && (m = line.match(OBJECT_KEY_RE))
          keys << m[1]
        end
        line.each_char do |ch|
          if ch == '{'
            depth += 1
            seen_open = true
          elsif ch == '}'
            depth -= 1
          end
        end
        break if seen_open && depth <= 0
        index += 1
        break if index - start > 200
      end
      keys
    end

    # Like `collect_object_keys`, but captures each entry's quoted string
    # *value* instead of its key (used for `alias: { h: 'help' }`, where the
    # canonical flag name is the value, not the short-flag key).
    private def collect_object_values(lines : Array(String), start : Int32) : Array(String)
      values = [] of String
      depth = 0
      seen_open = false
      index = start
      while index < lines.size
        line = lines[index]
        if seen_open && depth == 1 && (m = line.match(OBJECT_VALUE_RE))
          values << m[1]
        end
        line.each_char do |ch|
          if ch == '{'
            depth += 1
            seen_open = true
          elsif ch == '}'
            depth -= 1
          end
        end
        break if seen_open && depth <= 0
        index += 1
        break if index - start > 200
      end
      values
    end

    # Collects every quoted string literal inside the `[...]` array that
    # opens on/after `start` (e.g. `boolean: ['verbose', 'dry-run']`).
    private def collect_bracket_strings(lines : Array(String), start : Int32) : Array(String)
      values = [] of String
      depth = 0
      seen_open = false
      index = start
      while index < lines.size
        line = lines[index]
        line.scan(STRING_LIT_RE) { |sm| values << sm[1] }
        line.each_char do |ch|
          if ch == '['
            depth += 1
            seen_open = true
          elsif ch == ']'
            depth -= 1
          end
        end
        break if seen_open && depth <= 0
        index += 1
        break if index - start > 200
      end
      values
    end

    # Finds the index of the line where the balanced pair opened on `start`
    # (counting `open_ch`/`close_ch`, e.g. `(`/`)`) closes.
    private def brace_bounded_end(lines : Array(String), start : Int32, open_ch : Char, close_ch : Char) : Int32
      depth = 0
      seen_open = false
      index = start
      while index < lines.size
        lines[index].each_char do |ch|
          if ch == open_ch
            depth += 1
            seen_open = true
          elsif ch == close_ch
            depth -= 1
          end
        end
        break if seen_open && depth <= 0
        index += 1
        break if index - start > 400
      end
      index < lines.size ? index : lines.size - 1
    end

    # Extracts (name, param_type) pairs from each top-level `{...}` entry in
    # the command-line-args option array bounded by [start, stop] (inclusive
    # line indices). Each entry is scanned as its own brace-bounded block —
    # never a single-line regex — so Prettier-style multi-line-per-key
    # formatting (`{\n  name: 'x',\n  type: Boolean,\n}`) is captured too.
    private def cla_option_entries(lines : Array(String), start : Int32, stop : Int32) : Array(Tuple(String, String))
      results = [] of Tuple(String, String)
      depth = 0
      in_entry = false
      entry_lines = [] of String
      index = start
      while index <= stop && index < lines.size
        line = lines[index]
        line.each_char do |ch|
          if ch == '{'
            depth += 1
            in_entry = true
          elsif ch == '}'
            depth -= 1
          end
        end
        entry_lines << line if in_entry
        if in_entry && depth == 0
          text = entry_lines.join(" ")
          if (nm = text.match(CLA_NAME_RE)) && text.matches?(CLA_TYPE_KEY_RE)
            ptype = text.includes?("defaultOption") ? "argument" : "flag"
            results << {nm[1], ptype}
          end
          entry_lines = [] of String
          in_entry = false
        end
        index += 1
      end
      results
    end

    # citty also allows a subcommand to be declared as its own top-level
    # `const NAME = defineCommand({...})` and merely referenced by identifier
    # from `subCommands: { key: NAME }`, instead of nesting the
    # `defineCommand` call inline. Resolves those same-file references to
    # (start_line, end_line, url) so the block's `args:` header attributes to
    # `<root>/<key>` rather than falling back to root. Cross-file / lazy
    # subcommand references (`serve: () => import('./serve')...`) aren't
    # resolvable from a single file and are intentionally left unhandled.
    private def resolve_citty_var_subcommands(lines : Array(String), root_url : String) : Array(Tuple(Int32, Int32, String))
      var_bounds = {} of String => Tuple(Int32, Int32)
      lines.each_with_index do |line, idx|
        if m = line.match(CITTY_DEFINE_ASSIGN_RE)
          var_bounds[m[1]] = {idx, brace_bounded_end(lines, idx, '{', '}')}
        end
      end
      return [] of Tuple(Int32, Int32, String) if var_bounds.empty?

      resolved = [] of Tuple(Int32, Int32, String)
      index = 0
      while index < lines.size
        if lines[index].matches?(CITTY_SUBCOMMANDS_HEADER)
          block_end = brace_bounded_end(lines, index, '{', '}')
          ((index + 1)..block_end).each do |i|
            next unless i < lines.size
            if m = lines[i].match(CITTY_SUBCOMMAND_REF_RE)
              if bounds = var_bounds[m[2]]?
                resolved << {bounds[0], bounds[1], "#{root_url}/#{m[1]}"}
              end
            end
          end
          index = block_end
        end
        index += 1
      end
      resolved
    end

    # arg: `arg({ '--name': String, '-n': '--name' })`. Keys whose value is a
    # quoted string reference another flag (an alias) and are skipped.
    private def arg_flags(lines : Array(String), start : Int32) : Array(String)
      flags = [] of String
      depth = 0
      seen_open = false
      index = start
      while index < lines.size
        line = lines[index]
        if seen_open && depth == 1 && (m = line.match(ARG_KEY_RE))
          value = m[2].strip
          flags << m[1].lstrip('-') unless value.starts_with?('\'') || value.starts_with?('"')
        end
        line.each_char do |ch|
          if ch == '{'
            depth += 1
            seen_open = true
          elsif ch == '}'
            depth -= 1
          end
        end
        break if seen_open && depth <= 0
        index += 1
        break if index - start > 200
      end
      flags
    end

    # getopts: extracts flag names out of the option-config object passed as
    # the 2nd argument, bounded to the `getopts(...)` call itself so a
    # same-named `alias`/`default` object elsewhere in the file isn't picked
    # up.
    private def getopts_flags(lines : Array(String), start : Int32, block_end : Int32) : Array(String)
      block = lines[start..block_end]
      flags = [] of String
      if idx = block.index(&.matches?(GETOPTS_ALIAS_HEADER))
        flags.concat(collect_object_values(block, idx))
      end
      if idx = block.index(&.matches?(GETOPTS_DEFAULT_HEADER))
        flags.concat(collect_object_keys(block, idx))
      end
      if idx = block.index(&.matches?(GETOPTS_BOOLEAN_HEADER))
        flags.concat(collect_bracket_strings(block, idx))
      end
      if idx = block.index(&.matches?(GETOPTS_STRING_HEADER))
        flags.concat(collect_bracket_strings(block, idx))
      end
      flags.uniq
    end

    # Maps each package.json directory to its CLI binary name (the `bin` key,
    # or the package `name`), so endpoints carry the real executable name.
    private def collect_package_names : Array(Tuple(String, String))
      names = [] of Tuple(String, String)
      get_files_by_extension(".json").each do |path|
        next unless File.basename(path) == "package.json"
        begin
          content = read_file_content(path)
        rescue
          next
        end
        name = nil
        if m = content.match(/"bin"\s*:\s*\{\s*['"]?([A-Za-z0-9_.@\/-]+)['"]?\s*:/)
          name = m[1]
        elsif m = content.match(/"name"\s*:\s*['"]([^'"]+)['"]/)
          name = m[1]
        end
        next unless name
        names << {name.split('/').last, File.expand_path(File.dirname(path))}
      end
      names.sort_by! { |(_n, dir)| -dir.size }
      names
    end

    private def js_binary_name(names : Array(Tuple(String, String)), path : String) : String
      expanded = File.expand_path(File.dirname(path))
      names.each do |name, dir|
        return name if expanded == dir || expanded.starts_with?("#{dir}/")
      end
      File.basename(path, File.extname(path))
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
