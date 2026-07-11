require "../../../models/analyzer"

module Analyzer::Clojure
  # Surfaces the command-line attack surface of Clojure programs as `cli://`
  # endpoints: clojure.tools.cli option specs, cli-matic config,
  # babashka.cli spec/dispatch tables, environ.core env lookups, and
  # *command-line-args* / (System/getenv). Line-scan, merged by URL.
  class Cli < Analyzer
    TOOLS_CLI_LONG = /"--([A-Za-z0-9][\w-]*)/
    TOOLS_CLI_SPEC = /\[\s*(?:(?:"-[A-Za-z0-9]"|nil)\s+)?"--/
    MATIC_COMMAND  = /:command\s+"([^"]+)"/
    MATIC_OPTION   = /:option\s+"([A-Za-z0-9][\w-]*)"/
    NTH_ARGS       = /\(\s*nth\s+(?:\*command-line-args\*|args)\s+(\d+)/
    GET_ENV        = /\(\s*System\/getenv\s+"([^"]+)"/
    # Whole `:cmds [...]` vector (may hold several segments, e.g. `["docker" "start"]`).
    BB_CMDS = /:cmds\s+\[([^\]]*)\]/
    # `env` bound bare from environ.core: `(:require [environ.core :refer [env]])`.
    # Never trust an alias (`:as environ`) or an unrelated local/param named `env`.
    ENVIRON_REFER_ENV = /environ\.core\s*:refer\s*\[[^\]]*\benv\b/
    ENVIRON_ENV       = /\(\s*env\s+:([A-Za-z][\w-]*)/

    # NOTE: environ.core is intentionally absent here. It's a generic
    # 12-factor config-reading library used by web apps/workers/services just
    # as much as CLIs (same category as bare System/getenv, below) — it must
    # never gate CLI detection on its own. It only annotates params on a
    # `cli://` endpoint some OTHER marker below already established.
    MARKERS = /clojure\.tools\.cli\b|\(\s*(?:[\w.-]+\/)?parse-opts\b|\bcli-matic\b|\*command-line-args\*|\bbabashka\.cli\b/
    WEB_RE  = /\b(?:compojure|ring\.adapter|reitit|io\.pedestal|httpkit|aleph)\b/

    def analyze
      endpoints = {} of String => Endpoint
      [".clj", ".cljs", ".cljc"].each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cli_test_path?(path)
          next unless File.exists?(path)
          begin
            content = read_file_content(path)
            next unless content.matches?(MARKERS)
            root_url = "cli://#{cli_binary_name(path)}"
            emit_env = !content.matches?(WEB_RE)
            environ_env_ok = content.matches?(ENVIRON_REFER_ENV)
            current_url = root_url

            # babashka.cli dispatch tables are parsed structurally (brace
            # extents), not via a line-ordered sticky cursor: map literals are
            # unordered, so `:spec` can precede its own `:cmds` sibling, and a
            # stale cursor would misattribute options to the wrong (or a
            # previous) subcommand. Each `:spec` map's options are only ever
            # attributed to the `:cmds` entry that structurally encloses it.
            if content.includes?("babashka.cli")
              collect_babashka_dispatch(content, root_url, path, endpoints)
            end

            content.each_line.with_index do |line, index|
              line_no = index + 1
              if m = line.match(MATIC_COMMAND)
                current_url = "#{root_url}/#{m[1]}"
                fetch_endpoint(endpoints, current_url, path, line_no)
              end
              # tools.cli option vectors: ["-p" "--port PORT" ...]. `scan` so
              # several vectors on one line (and the long-only form) all surface.
              if line.matches?(TOOLS_CLI_SPEC)
                line.scan(TOOLS_CLI_LONG) { |lm| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(lm[1], "", "flag")) }
              end
              if m = line.match(MATIC_OPTION)
                fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(NTH_ARGS)
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
              end
              if emit_env
                line.scan(GET_ENV) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
                # environ.core: (env :database-url) reads DATABASE_URL (env var,
                # system property, or .lein-env) — surface the conventional
                # upper-snake env var name it resolves to. Only once we've
                # confirmed `env` is actually environ.core's var (environ_env_ok),
                # never for an aliased require or an unrelated `env` binding.
                if environ_env_ok
                  line.scan(ENVIRON_ENV) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1].upcase.gsub('-', '_'), "", "env")) }
                end
              end
            end
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, File.extname(path))
      if stem == "core" || stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("_test.")
    end

    private def fetch_endpoint(endpoints : Hash(String, Endpoint), url : String,
                               path : String, line_no : Int32) : Endpoint
      endpoints[url] ||= begin
        ep = Endpoint.new(url, "CLI", Details.new(PathInfo.new(path, line_no)))
        ep.protocol = "cli"
        ep
      end
    end

    # Finds every babashka.cli dispatch-table entry (`{:cmds [...] :spec {...}}`)
    # by brace extent rather than line order, then attributes each `:spec`
    # map's options only to the entry that structurally contains it.
    private def collect_babashka_dispatch(content : String, root_url : String, path : String,
                                           endpoints : Hash(String, Endpoint)) : Nil
      pairs = brace_pairs(content)

      entries = [] of {Int32, Int32, String}
      content.scan(BB_CMDS) do |m|
        match_start = m.byte_begin(0)
        match_end = m.byte_end(0)
        segments = m[1].scan(/"([^"\\]*)"/).map { |sm| sm[1] }
        next if segments.empty?
        enclosing = pairs.select { |(o, c)| o <= match_start && c >= match_end }.min_by? { |(o, c)| c - o }
        next unless enclosing
        o, c = enclosing
        entries << {o, c, segments.join("/")}
      end

      # A dispatch entry surfaces its `cli://root/cmd` endpoint even if its
      # `:spec` map is empty/absent (e.g. a bare `help` subcommand).
      entries.each do |(o, _, segments)|
        fetch_endpoint(endpoints, "#{root_url}/#{segments}", path, line_number_for(content, o))
      end

      content.scan(/:spec\s*(\{)/) do |m|
        spec_open = m.byte_begin(1)
        spec_close = find_matching_delimiter(content, spec_open, '{', '}', content.bytesize)
        owner = entries.find { |(o, c, _)| o <= spec_open && spec_close <= c }
        target_url = owner ? "#{root_url}/#{owner[2]}" : root_url
        spec_options(content, spec_open, spec_close).each do |(opt_name, key_pos)|
          fetch_endpoint(endpoints, target_url, path, line_number_for(content, key_pos)).push_param(Param.new(opt_name, "", "flag"))
        end
      end
    end

    # Direct (depth-1) `:key {...}` children of a `:spec` map — i.e. the
    # option entries themselves, never a nested sub-map inside one of those
    # option entries (e.g. babashka.cli's `:validate {:fn ... :ex-msg ...}`).
    # Matching the general `:key {...}` shape (not requiring `:coerce`) also
    # picks up untyped/default-string options like `{:desc "..."}`.
    private def spec_options(content : String, spec_open : Int32, spec_close : Int32) : Array({String, Int32})
      results = [] of {String, Int32}
      i = spec_open + 1
      depth = 1
      while i < spec_close
        char = content.byte_at(i).unsafe_chr
        case char
        when ';'
          i = skip_comment(content, i, spec_close)
        when '"'
          i = skip_string(content, i, spec_close)
        when '{'
          depth += 1
        when '}'
          depth -= 1
        when ':'
          if depth == 1
            rest = content.byte_slice(i, spec_close - i)
            if km = rest.match(/\A:([A-Za-z][\w-]*)\s*\{/)
              results << {km[1], i}
            end
          end
        end
        i += 1
      end
      results
    end

    # Every matched `{...}` pair in `content`, as byte-offset (open, close).
    private def brace_pairs(content : String) : Array({Int32, Int32})
      pairs = [] of {Int32, Int32}
      stack = [] of Int32
      i = 0
      limit = content.bytesize
      while i < limit
        char = content.byte_at(i).unsafe_chr
        case char
        when ';'
          i = skip_comment(content, i, limit)
        when '"'
          i = skip_string(content, i, limit)
        when '{'
          stack.push(i)
        when '}'
          if open = stack.pop?
            pairs << {open, i}
          end
        end
        i += 1
      end
      pairs
    end

    private def skip_comment(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit && source.byte_at(i).unsafe_chr != '\n'
        i += 1
      end
      i
    end

    private def skip_string(source : String, index : Int32, limit : Int32) : Int32
      i = index + 1
      escaping = false

      while i < limit
        char = source.byte_at(i).unsafe_chr
        if escaping
          escaping = false
        elsif char == '\\'
          escaping = true
        elsif char == '"'
          return i
        end
        i += 1
      end

      limit - 1
    end

    private def find_matching_delimiter(source : String, index : Int32, open_char : Char, close_char : Char, limit : Int32) : Int32
      depth = 0
      i = index

      while i < limit
        char = source.byte_at(i).unsafe_chr
        case char
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          i = skip_string(source, i, limit)
        when open_char
          depth += 1
        when close_char
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end

      index
    end

    private def line_number_for(source : String, index : Int32) : Int32
      source.byte_slice(0, index).count('\n') + 1
    end
  end
end
