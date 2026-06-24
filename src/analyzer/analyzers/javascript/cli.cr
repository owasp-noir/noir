require "../../../models/analyzer"
require "../../engines/javascript_engine"

module Analyzer::Javascript
  # Surfaces the command-line attack surface of JavaScript/TypeScript programs
  # (Node, Deno, Bun) as `cli://` endpoints: one endpoint per (sub)command
  # with named options (param_type "flag"), positional arguments ("argument")
  # and consumed environment variables ("env"). Covers the `util.parseArgs`
  # builtin plus commander, yargs, cac, sade, meow and minimist. A single
  # analyzer scans every JS/TS extension so a `.ts` CLI isn't double-counted.
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
      CLI_MARKERS.any? { |m| content.includes?(m) } || content.matches?(ARGV_SLICE)
    end

    private def js_test_or_vendor?(path : String) : Bool
      path.includes?("/node_modules/") || path.includes?("/__tests__/") ||
        path.includes?(".test.") || path.includes?(".spec.") || path.includes?(".d.ts")
    end

    private def scan(lines : Array(String), path : String, root_url : String,
                     endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url

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
