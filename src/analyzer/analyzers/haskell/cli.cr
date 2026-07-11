require "../../../models/analyzer"

module Analyzer::Haskell
  # Surfaces the command-line attack surface of Haskell programs as `cli://`
  # endpoints: optparse-applicative (long/argument/command), turtle
  # (Turtle.Options: optText/optInt/optPath/switch/arg/argText) plus getEnv
  # reads. Line-scan, merged by URL.
  class Cli < Analyzer
    LONG     = /(?<![A-Za-z0-9_'])long\s+"([A-Za-z0-9][\w-]*)"/
    ARGUMENT = /(?<![A-Za-z0-9_'])argument\b.*?\bmetavar\s+"([A-Za-z0-9][\w-]*)"/
    COMMAND  = /(?<![A-Za-z0-9_'])command\s+"([A-Za-z0-9][\w-]*)"/
    GET_ENV  = /(?<![A-Za-z0-9_'])(?:getEnv|lookupEnv)\s+"([A-Za-z0-9_]\w*)"/

    # Turtle.Options: optText/optInt/optPath/... and switch take the flag
    # name as their own first quoted argument (no `long "..."` wrapper),
    # so these need dedicated regexes distinct from LONG above.
    TURTLE_OPT = /(?<![A-Za-z0-9_'])opt(?:Text|Int|Integer|Double|Path|Read|Bool)\s+"([A-Za-z0-9][\w-]*)"/
    # `switch` is a bare, extremely common Haskell identifier (also used by
    # optparse-applicative itself, and as a plain string-pattern dispatch
    # function). Real Turtle usage is always the full 3-argument shape
    # `switch "name" 'c' "desc"`; require the trailing short-char + description
    # so we don't fire on unrelated `switch "x" = ...` equations.
    TURTLE_SWITCH = /(?<![A-Za-z0-9_'])switch\s+"([A-Za-z0-9][\w-]*)"\s+'.'\s+"[^"]*"/
    # argText plus the type-suffixed positional combinators, mirroring the
    # TURTLE_OPT alternation above.
    TURTLE_ARG = /(?<![A-Za-z0-9_'])arg(?:Text|Int|Integer|Double|Read|Path)\s+"([A-Za-z0-9][\w-]*)"/
    # `arg` (the generic reader-based combinator) is an even more common bare
    # word than `switch` (ordinary local variables/parameters are routinely
    # named `arg`). Real usage is always `arg <reader> "name" "desc"`: the
    # reader is an identifier/qualified-name or a parenthesized expression,
    # and BOTH the name and description string literals are required -- a
    # stray `f arg x "str"` call/comment only has one trailing string and
    # won't match.
    TURTLE_ARG_FN = /(?<![A-Za-z0-9_'])arg\s+(?:[A-Za-z_][\w.']*|\([^()]*\))\s+"([A-Za-z0-9][\w-]*)"\s+"[^"]*"/

    # Turtle re-exports Turtle.Options from the top-level Turtle module,
    # which is used pervasively for plain shell scripting too, so gate on
    # either the qualified submodule import or an explicit `options` name
    # in the unqualified import list, never a bare `import Turtle`.
    TURTLE_MARKERS = /\bimport\s+(?:qualified\s+)?Turtle\.Options\b|\bimport\s+(?:qualified\s+)?Turtle\b\s*\([^)]*\boptions\b[^)]*\)/

    MARKERS = /\bimport\s+(?:qualified\s+)?Options\.Applicative\b|\b(?:execParser|strOption|subparser|hsubparser)\b|\bimport\s+(?:qualified\s+)?System\.Console\.(?:GetOpt|CmdArgs)\b|\bgetArgs\b|#{TURTLE_MARKERS}/
    WEB_RE  = /\bimport\s+(?:qualified\s+)?(?:Web\.Scotty|Servant|Yesod|Network\.Wai)\b/

    # Per-path test-file gate. A precompiled `Regex.union` (PCRE2 JIT)
    # replaces the two OR-ed `String#includes?` scans it used to run --
    # provably equivalent since union auto-escapes each literal, and a
    # single regex pass over `lower` is cheaper than two substring scans.
    TEST_PATH_RE = Regex.union("/test/", "_spec.")

    def analyze
      endpoints = {} of String => Endpoint
      [".hs", ".lhs"].each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cli_test_path?(path)
          next unless File.exists?(path)
          begin
            content = read_file_content(path)
            next unless content.matches?(MARKERS)
            root_url = "cli://#{cli_binary_name(path)}"
            emit_env = !content.matches?(WEB_RE)
            content.each_line.with_index do |raw_line, index|
              line_no = index + 1
              # Strip trailing `-- ...` line comments before matching so
              # commented-out/stale code (e.g. `-- arg count "old" "x"`)
              # never contributes bogus params.
              line = strip_line_comment(raw_line)
              # optparse-applicative defines subcommand option parsers in
              # separate top-level bindings, so a sticky cursor would
              # misattribute later root globals. Scope a `command "x"` only to
              # options on the SAME line (the common inline shape); otherwise
              # attribute to the root.
              target = root_url
              if m = line.match(COMMAND)
                target = "#{root_url}/#{m[1]}"
                fetch_endpoint(endpoints, target, path, line_no)
              end
              if m = line.match(LONG)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(ARGUMENT)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1].downcase, "", "argument"))
              end
              if m = line.match(TURTLE_OPT)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(TURTLE_SWITCH)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(TURTLE_ARG)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "argument"))
              end
              if m = line.match(TURTLE_ARG_FN)
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "argument"))
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
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, File.extname(path))
      if stem == "Main" || stem == "main" || stem == "Cli" || stem == "App"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    # Truncates a line at the start of a `--` line comment, ignoring any
    # `--` that appears inside a double-quoted string literal. Naive (no
    # handling of nested block comments or non-string escapes beyond `\"`)
    # but sufficient to keep stale/commented-out code from feeding the
    # option/argument extractors above.
    private def strip_line_comment(line : String) : String
      in_string = false
      escaped = false
      chars = line.chars
      chars.each_with_index do |c, i|
        if in_string
          if escaped
            escaped = false
          elsif c == '\\'
            escaped = true
          elsif c == '"'
            in_string = false
          end
        else
          if c == '"'
            in_string = true
          elsif c == '-' && chars[i + 1]? == '-'
            return chars[0...i].join
          end
        end
      end
      line
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
