require "../../models/analyzer"
require "../../miniparsers/ruby_callee_extractor"

module Analyzer::Ruby
  abstract class RubyEngine < Analyzer
    HTTP_VERBS = ["get", "post", "put", "delete", "patch", "head", "options"]

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The verb set is fixed, so precompile the
    # `<verb> "<path>"` matchers once at load time.
    VERB_ROUTE_PATTERNS = HTTP_VERBS.map do |verb|
      {verb, /^#{verb}\s*\(?\s*['"](.+?)['"]/}
    end

    # Minitest's `*_test.rb` and RSpec's `*_spec.rb` conventions are
    # rigid in Ruby — `rake test` / `mri test` only run files matching
    # the first, and `rspec` discovers the second. Production Ruby
    # never adopts either filename, so the suffix check is safe for
    # every Ruby analyzer (sinatra, grape, roda, hanami). Promoted
    # from `Analyzer::Ruby::Sinatra` (#1571) so the rest of the
    # family stays in sync.
    #
    # Test::Unit / Minitest equally support the inverse `test_*.rb`
    # prefix (`rake test` globs `test/test_*.rb`). gollum, for
    # instance, exercises its modular Sinatra app exclusively through
    # `test/test_app.rb`-style files whose inline Rack::Test requests
    # (`get "/wiki/Home"`, `post "/gollum/upload_file"`) are
    # indistinguishable from real route registrations to a line-based
    # matcher — ~70 phantom endpoints per scan. Production route files
    # never carry the `test_` prefix, so it is as safe as the suffix
    # forms. We match on the basename only (never the full path) so a
    # legitimate app that merely lives under a `spec/`-suffixed
    # absolute path — e.g. noir's own fixtures — is untouched.
    def self.ruby_test_path?(path : String) : Bool
      base = File.basename(path)
      return true if base.ends_with?("_test.rb") || base.ends_with?("_spec.rb")
      return true if base.starts_with?("test_") && base.ends_with?(".rb")
      false
    end

    RUBY_NON_PRODUCTION_DIRS = Set{
      "spec", "test", "tests", "features",
      "benchmark", "benchmarks", "examples",
      "coverage", "tmp",
    }

    # Whole-tree Ruby analyzers (Sinatra/Grape/Roda/WEBrick) otherwise see
    # Rack test helpers, benchmark apps, and framework examples as live
    # services. Match these directories only relative to the configured scan
    # root so noir's own fixture tree under `spec/functional_test/fixtures`
    # is not accidentally skipped when the fixture directory itself is the
    # base path.
    protected def ruby_non_production_path?(path : String) : Bool
      return true if RubyEngine.ruby_test_path?(path)

      relative = ruby_relative_path(path).gsub('\\', '/')
      RUBY_NON_PRODUCTION_DIRS.any? do |dir|
        relative == dir || relative.starts_with?("#{dir}/") || relative.includes?("/#{dir}/")
      end
    end

    private def ruby_relative_path(path : String) : String
      normalized = normalized_configured_base_for(path)
      return File.basename(path) unless normalized

      expanded = CodeLocator.instance.expanded_path_for(path)
      return File.basename(path) unless Noir::PathScope.under_normalized_root?(expanded, normalized)

      relative = expanded[normalized.size..].lchop(File::SEPARATOR)
      relative.empty? ? File.basename(path) : relative
    end

    private def normalized_configured_base_for(path : String) : String?
      return @normalized_base_paths.first?.try(&.[1]) if @normalized_base_paths.size <= 1

      base = configured_base_for(path)
      @normalized_base_paths.each do |candidate, normalized|
        return normalized if candidate == base
      end
      nil
    end

    # Match the `<verb> "<path>"` idiom on a single line and return the first
    # endpoint found, or an empty endpoint if none match. Shared by Hanami
    # and Sinatra (Rails uses a different per-line-multi-match shape).
    def line_to_endpoint(content : String, details : Details? = nil) : Endpoint
      # Anchor the verb to the start of the (stripped) line so a
      # string literal that happens to *contain* a DSL verb stays
      # out — `hint = "Try get '/from-string' do ... end"` was
      # picking up `/from-string` as a real route pre-fix. Anything
      # the Sinatra/Hanami DSL accepts is invoked at statement
      # start (possibly after a block opener), so this is a tight
      # constraint without false-negatives in the bundled fixtures.
      leading = content.lstrip
      VERB_ROUTE_PATTERNS.each do |verb, verb_pattern|
        next if !leading.starts_with?(verb)
        next if leading.size > verb.size && (leading[verb.size].alphanumeric? || leading[verb.size] == '_')

        if m = leading.match(verb_pattern)
          path = normalize_ruby_interpolation(m[1])
          # Sinatra/Hanami route patterns are always rooted at `/` (or an
          # interpolated `{prefix}` segment). The verb words double as
          # ordinary Ruby methods — ActiveRecord migrations run
          # `delete "DELETE FROM articles WHERE ..."`, HTTP clients call
          # `post "https://..."`, etc. — so a string argument that isn't a
          # rooted path is not a route. Without this guard the Sinatra
          # analyzer (which scans every `.rb` file) turned raw SQL into
          # phantom `DELETE /DELETE FROM ...` endpoints.
          next unless path.starts_with?('/') || path.starts_with?('{')
          if details
            return Endpoint.new(path, verb.upcase, details)
          else
            return Endpoint.new(path, verb.upcase)
          end
        end
      end
      Endpoint.new("", "")
    end

    # Ruby's `"#{expr}"` interpolation in a route literal — e.g.
    # `get "#{PREFIX}/items"` — used to leak the raw `#{PREFIX}`
    # text into the URL. Rewrite it as a `{expr}` placeholder so
    # downstream output formats see a sensible path template AND
    # the path-parameter extractor can register the placeholder
    # name. Same shape as the Python f-string fix.
    private def normalize_ruby_interpolation(path : String) : String
      path.gsub(/\#\{([^}]+)\}/) { |_| "{#{$~[1].strip}}" }
    end

    # Locate the directories that host a known framework anchor file
    # (e.g. `config/routes.rb`) anywhere under `base_paths`. Returns the
    # framework root for each match, i.e. the anchor's path with the
    # relative suffix stripped. Lets analyzers stop assuming the framework
    # root is `@base_path` and survive monorepos where it lives in a
    # subdirectory (`App/`, `backend/`, ...).
    protected def discover_framework_roots(anchor : String) : Array(String)
      suffix = anchor.starts_with?("/") ? anchor : "/#{anchor}"
      roots = [] of String

      all_files.each do |file|
        next unless file.ends_with?(suffix)
        next unless base_paths.any? { |base| path_under_root?(file, base) }

        root = file[0, file.size - suffix.size]
        roots << root unless roots.includes?(root)
      end

      roots
    end

    # Walk the project file tree in parallel, invoking the block for each
    # readable non-directory file. Used by analyzers that scan the whole
    # tree (Sinatra); Rails/Hanami target specific config files directly.
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end

    protected def attach_ruby_callees(endpoint : Endpoint, callees : Array(Noir::RubyCalleeExtractor::Entry))
      Noir::RubyCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_ruby_do_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      start_line = Noir::RubyCalleeExtractor.strip_comment(lines[start_index]).strip
      match = start_line.match(/\bdo\b(?:\s*\|[^|]*\|)?(.*)$/)
      return unless match

      body_lines = [] of String
      body_start_line = start_index + 2
      depth = 1
      tail = match[1].strip
      tail = tail[1, tail.size - 1].strip if tail.starts_with?(";")

      unless tail.empty?
        body_start_line = start_index + 1
        if m = tail.match(/^(.*?)(?:;\s*)?end\b/)
          return {m[1].strip, body_start_line}
        end

        body_lines << tail
        depth += ruby_do_block_open_delta(tail)
      end

      index = start_index + 1
      while index < lines.size
        raw_body_line = lines[index]
        body_line = Noir::RubyCalleeExtractor.strip_comment(raw_body_line).strip

        if ruby_closes_block?(body_line)
          depth -= 1
          break if depth == 0
          body_lines << raw_body_line
          index += 1
          next
        end

        body_lines << raw_body_line
        depth += ruby_do_block_open_delta(body_line)
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    protected def ruby_do_block_open_delta(line : String) : Int32
      return 0 if line.empty?
      return 1 if line.match(/\bdo\b/) && !line.match(/\bend\b/)
      return 1 if line.match(/(?:^|=[^=>])\s*(if|unless|case|begin|while|until|for|class|module|def)\b/) && !line.match(/\bend\b/)
      0
    end

    private def ruby_closes_block?(line : String) : Bool
      !!line.match(/^end\b/)
    end
  end
end
