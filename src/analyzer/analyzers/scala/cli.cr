require "../../../models/analyzer"

module Analyzer::Scala
  # Surfaces the command-line attack surface of Scala programs as `cli://`
  # endpoints: scopt/decline (options/args/subcommands), Scallop
  # (ScallopConf options/args/subcommands), com.twitter.app (flags), and
  # sys.env reads. Line-scan, merged by URL.
  #
  # Each library is gated on its own distinct import/marker, and only that
  # library's regex family runs against the file. This matters because
  # Scallop's bare `opt[T]("name")` call is textually identical to scopt's
  # `opt[T]("name")` -- without per-library gating, scopt's extractor would
  # also fire on Scallop code and attach subcommand-only flags to the root
  # endpoint even though Scallop's own subcommand scoping correctly bound
  # them to the subcommand.
  class Cli < Analyzer
    # --- scopt / decline -----------------------------------------------
    SCOPT_OPT = /\bopt\[[^\]]*\]\s*\(\s*(?:'[A-Za-z0-9]'\s*,\s*)?"([^"]+)"/
    SCOPT_ARG = /\barg\[[^\]]*\]\s*\(\s*"<?([A-Za-z0-9][\w-]*)>?"/
    SCOPT_CMD = /\bcmd\s*\(\s*"([^"]+)"/
    DEC_OPT   = /\bOpts\.option\[[^\]]*\]\s*\(\s*"([^"]+)"/
    DEC_FLAG  = /\bOpts\.flag\s*\(\s*"([^"]+)"/
    DEC_ARG   = /\bOpts\.argument(?:\[[^\]]*\])?\s*\(\s*"<?([A-Za-z0-9][\w-]*)>?"/
    DEC_CMD   = /\bCommand\s*\(\s*"([^"]+)"/

    SCOPT_DECLINE_MARKER = /\bscopt\b|\bOParser\b|\bcom\.monovore\.decline\b|\bOpts\.(?:option|flag|argument|arguments)\b|\bmainargs\b/

    # --- Scallop (org.rogach.scallop) -----------------------------------
    # `opt[T]`/`trailArg[T]` take an explicit name, or (via a Scallop macro)
    # infer it from the enclosing `val` when the name is omitted -- this is
    # a real, documented Scallop feature, unlike com.twitter.app's `flag`.
    #
    # Subcommands are declared either as `val x = (new )?Subcommand("name")
    # { ... }` or the idiomatic `object x extends Subcommand("name") { ... }`
    # shown in Scallop's own docs; both open their scope with a `{` on the
    # same line, closed via brace-depth tracking.
    SCALLOP_SUBCMD       = /\b(?:val\s+\w+\s*=\s*(?:new\s+)?Subcommand\s*\(\s*"([^"]+)"|object\s+\w+\s+extends\s+Subcommand\s*\(\s*"([^"]+)")/
    SCALLOP_OPT_NAMED    = /\bopt\[[^\]]*\]\s*\(\s*"([^"]+)"/
    SCALLOP_OPT_INFERRED = /\bval\s+(\w+)\s*=\s*opt\[[^\]]*\]\s*\(\s*(?!")/
    SCALLOP_ARG_NAMED    = /\btrailArg\[[^\]]*\]\s*\(\s*"([^"]+)"/
    SCALLOP_ARG_INFERRED = /\bval\s+(\w+)\s*=\s*trailArg\[[^\]]*\]\s*\(\s*(?!")/

    SCALLOP_MARKER = /\borg\.rogach\.scallop\b|\bScallopConf\b/

    # --- com.twitter.app --------------------------------------------------
    # `flag[T]("name", ...)` always requires an explicit name -- there is no
    # reflection/macro-based no-arg overload the way Scallop infers names
    # from a `val`, so only the explicitly-named form is extracted.
    TWITTER_FLAG = /\bflag\[[^\]]*\]\s*\(\s*"([^"]+)"/

    TWITTER_MARKER = /\bcom\.twitter\.app\b/

    SYS_ENV = /\bsys\.env\s*(?:\(\s*"([^"]+)"|\.get\s*\(\s*"([^"]+)")/

    MARKERS = /\bscopt\b|\bOParser\b|\bcom\.monovore\.decline\b|\bOpts\.(?:option|flag|argument|arguments)\b|\bmainargs\b|\borg\.rogach\.scallop\b|\bScallopConf\b|\bcom\.twitter\.app\b/
    WEB_RE  = /\bimport\s+(?:akka\.http|play\.api|org\.http4s|cask|com\.twitter\.finatra|com\.linecorp\.armeria|zhttp|zio\.http)\b/

    # One precompiled `Regex.union` scan (PCRE2 JIT) replaces four separate
    # `String#includes?` scans of the same buffer -- Crystal's `includes?` is
    # not Boyer-Moore accelerated, so a single regex pass over `lower` is
    # cheaper than four. Equivalent to the OR-of-substrings it replaces
    # (union escapes each literal).
    CLI_TEST_PATH_RE = Regex.union("/test/", "/it/", "spec.scala", "test.scala")

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".scala").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          next unless content.matches?(MARKERS)
          root_url = "cli://#{cli_binary_name(path)}"
          emit_env = !content.matches?(WEB_RE)

          # Decide, once per file, which library families are actually
          # present so their (textually overlapping) regexes never run
          # against a file that uses a different library.
          has_scopt_decline = content.matches?(SCOPT_DECLINE_MARKER)
          has_scallop = content.matches?(SCALLOP_MARKER)
          has_twitter = content.matches?(TWITTER_MARKER)

          pending_cmd_url = root_url
          in_children = false
          children_depth = 0

          pending_scallop_url = root_url
          in_subcommand = false
          subcommand_depth = 0

          content.each_line.with_index do |line, index|
            line_no = index + 1

            if has_scopt_decline
              if (m = line.match(SCOPT_CMD)) || (m = line.match(DEC_CMD))
                pending_cmd_url = "#{root_url}/#{m[1]}"
                fetch_endpoint(endpoints, pending_cmd_url, path, line_no)
              end
              # scopt scopes a subcommand's opts inside `.children( ... )`;
              # only there do options bind to the subcommand. Outside, they
              # (and any trailing root opts after the block) bind to root.
              in_children = true if line.includes?(".children(")
              target = in_children ? pending_cmd_url : root_url
              if (m = line.match(SCOPT_OPT)) || (m = line.match(DEC_OPT)) || (m = line.match(DEC_FLAG))
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if (m = line.match(SCOPT_ARG)) || (m = line.match(DEC_ARG))
                fetch_endpoint(endpoints, target, path, line_no).push_param(Param.new(m[1], "", "argument"))
              end
              if in_children
                children_depth += line.count('(') - line.count(')')
                if children_depth <= 0
                  in_children = false
                  children_depth = 0
                end
              end
            end

            if has_scallop
              if m = line.match(SCALLOP_SUBCMD)
                name = m[1]? || m[2]?
                if name
                  pending_scallop_url = "#{root_url}/#{name}"
                  fetch_endpoint(endpoints, pending_scallop_url, path, line_no)
                  in_subcommand = true
                end
              end
              # Subcommand bodies open their scope with a `{` on the same
              # line as the `Subcommand(...)`/`extends Subcommand(...)`
              # declaration; opts/args stay bound to it via brace-depth
              # tracking until the matching `}`.
              starget = in_subcommand ? pending_scallop_url : root_url
              if m = line.match(SCALLOP_OPT_NAMED)
                fetch_endpoint(endpoints, starget, path, line_no).push_param(Param.new(m[1], "", "flag"))
              elsif m = line.match(SCALLOP_OPT_INFERRED)
                fetch_endpoint(endpoints, starget, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
              if m = line.match(SCALLOP_ARG_NAMED)
                fetch_endpoint(endpoints, starget, path, line_no).push_param(Param.new(m[1], "", "argument"))
              elsif m = line.match(SCALLOP_ARG_INFERRED)
                fetch_endpoint(endpoints, starget, path, line_no).push_param(Param.new(m[1], "", "argument"))
              end
              if in_subcommand
                subcommand_depth += line.count('{') - line.count('}')
                if subcommand_depth <= 0
                  in_subcommand = false
                  subcommand_depth = 0
                end
              end
            end

            if has_twitter
              if m = line.match(TWITTER_FLAG)
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
              end
            end

            if emit_env
              line.scan(SYS_ENV) do |em|
                name = em[1]? || em[2]?
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "env")) if name
              end
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

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".scala")
      if stem == "Main" || stem == "main" || stem == "Cli" || stem == "App"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      path.downcase.matches?(CLI_TEST_PATH_RE)
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
