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
    # Exact translation of the three-way check this replaces:
    # `relative == dir` and `relative.starts_with?("#{dir}/")` collapse to
    # the leading branch, `relative.includes?("/#{dir}/")` to the second.
    # Deliberately NOT `(?:\A|\/)dir(?:\/|\z)`, which would also match a
    # trailing segment (`app/spec`) the old chain rejected.
    #
    # The chain built two interpolated Strings per directory per call —
    # 18 allocations on every Ruby file, for every whole-tree Ruby
    # analyzer — before scanning for each of them separately.
    RUBY_NON_PRODUCTION_PATH_RE = begin
      alternation = RUBY_NON_PRODUCTION_DIRS.join("|") { |dir| Regex.escape(dir) }
      Regex.new("\\A(?:#{alternation})(?:/|\\z)|/(?:#{alternation})/")
    end

    protected def ruby_non_production_path?(path : String) : Bool
      return true if RubyEngine.ruby_test_path?(path)

      relative = ruby_relative_path(path)
      relative = relative.gsub('\\', '/') if relative.includes?('\\')
      relative.matches?(RUBY_NON_PRODUCTION_PATH_RE)
    end

    private def ruby_relative_path(path : String) : String
      normalized = normalized_configured_base_for(path)
      return File.basename(path) unless normalized

      expanded = CodeLocator.instance.expanded_path_for(path)
      return File.basename(path) unless Noir::PathScope.under_normalized_root?(expanded, normalized)

      relative = expanded[normalized.size..].lchop('/')
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

    # Rails, Hanami and Sinatra all spell a route `get "/books" …`, and every
    # Ruby analyzer is handed every `.rb` file in the scan, so each one could
    # parse the others' route table with its own DSL. These two predicates
    # identify a file as unmistakably belonging to Rails or to Hanami; an
    # analyzer that is neither uses them to step aside.
    #
    # `Rails.application.routes.draw` and `Hanami::Routes` are positive
    # markers — a router that carries one is that framework's and nobody
    # else's. There is deliberately no Sinatra equivalent: a Sinatra route
    # file can be a bare `get "/x" do … end` with no framework reference at
    # all, which is why the checks run in this direction only.
    RAILS_ROUTER_RE  = /\.routes\.draw\b|ActionDispatch::Routing/
    HANAMI_ROUTER_RE = /Hanami::Rout|Hanami\.app\b|Hanami\.routes\b/

    protected def rails_router_source?(source : String) : Bool
      source.matches?(RAILS_ROUTER_RE)
    end

    protected def hanami_router_source?(source : String) : Bool
      source.matches?(HANAMI_ROUTER_RE)
    end

    protected def rails_router_file?(path : String) : Bool
      rails_router_source?(read_file_content(path))
    rescue
      false
    end

    protected def hanami_router_file?(path : String) : Bool
      hanami_router_source?(read_file_content(path))
    rescue
      false
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

    # Walk Ruby sources (`.rb` / `.ru`) in parallel. Used by analyzers
    # that scan the whole tree (Sinatra, Grape, Roda, WEBrick);
    # Rails/Hanami target specific config files directly. Candidates
    # come from the extension index so monorepo `file_map` entries in
    # other languages never enter the channel. Paths are detector-
    # registered regular files — no per-path `File.exists?` /
    # `File.directory?`.
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
    RUBY_SOURCE_EXTENSIONS = [".rb", ".ru"]

    protected def parallel_file_scan(&block : String -> Nil) : Nil
      scan_files(get_files_by_extensions(RUBY_SOURCE_EXTENSIONS), &block)
    end

    # The file's text with the parts Ruby never runs blanked out: `=begin` …
    # `=end` block comments, heredoc bodies, and everything after `__END__`.
    # Every line keeps its place (blanked lines become empty), so line
    # numbers and per-line walks are unaffected. Ruby analyzers read sources
    # through this instead of `read_file_content`.
    protected def ruby_source(path : String) : String
      RubyEngine.mask_non_code(read_file_content(path))
    end

    EVAL_CALL_RE          = /(?:\b|_)eval\b/
    RUBY_NON_CODE_HINT_RE = /^=begin|^__END__|<<[~-]?["'`]?[A-Za-z_]/m

    def self.mask_non_code(content : String) : String
      return content unless content.matches?(RUBY_NON_CODE_HINT_RE)

      lines = content.split('\n')
      index = HeredocTerminators.new(lines)
      in_block_comment = false
      changed = false
      i = 0
      while i < lines.size
        line = lines[i]
        if in_block_comment
          in_block_comment = false if ruby_directive?(line, "=end")
          lines[i] = ""
          changed = true
          i += 1
          next
        end

        if ruby_directive?(line, "=begin")
          in_block_comment = true
          lines[i] = ""
          changed = true
          i += 1
          next
        end

        if line.rstrip == "__END__"
          (i...lines.size).each { |j| lines[j] = "" }
          changed = true
          break
        end

        # A line can open several heredocs (`call(<<~A, <<~B)`); their bodies
        # follow one after another. An opener with no terminator below it was
        # a misread `<<` (a shift, an append), so it masks nothing.
        last = i
        evaluated = nil
        heredoc_openers(line) do |id, indented|
          terminator = index.after(id, last, indented)
          break unless terminator
          # A heredoc handed to `eval`/`class_eval`/`instance_eval`/
          # `module_eval` is Ruby that runs, whatever its id; `<<~RUBY` is
          # the convention for such code even when the eval is elsewhere.
          evaluated = line.matches?(EVAL_CALL_RE) if evaluated.nil?
          unless evaluated || id == "RUBY"
            (last + 1..terminator).each { |j| lines[j] = "" }
            changed = true
          end
          last = terminator
        end
        i = last + 1
      end

      changed ? lines.join('\n') : content
    end

    # `=begin`/`=end` must start the line and be the whole first word.
    private def self.ruby_directive?(line : String, word : String) : Bool
      line.starts_with?(word) && (line.bytesize == word.bytesize || line.byte_at(word.bytesize).unsafe_chr.ascii_whitespace?)
    end

    # Yields each heredoc opened on `line` as (identifier, terminator may be
    # indented). Strings and the trailing comment are skipped, and `<<` only
    # counts at the start of an operand, so `1<<FLAGS` stays a shift.
    private def self.heredoc_openers(line : String, &)
      return unless line.includes?("<<")

      size = line.bytesize
      # Inside a string-like literal: `quote` is the byte that closes it and,
      # for a bracketed `%w( … )`, `open` is the bracket that nests.
      quote = 0_u8
      open = 0_u8
      depth = 0
      j = 0
      while j < size
        byte = line.byte_at(j)
        if quote != 0
          if byte == '\\'.ord
            j += 1
          elsif open != 0 && byte == open
            depth += 1
          elsif byte == quote
            if depth > 0
              depth -= 1
            else
              quote = 0_u8
              open = 0_u8
            end
          end
        elsif byte == '"'.ord || byte == '\''.ord || byte == '`'.ord
          quote = byte
        elsif byte == '%'.ord && operand_start?(line, j) && (delimiter_at = percent_literal_delimiter(line, j))
          # `%w(…)`, `%(…)`, `%r{…}`, `%q[…]`: a string, whatever it holds.
          delimiter = line.byte_at(delimiter_at)
          quote = PERCENT_CLOSERS[delimiter]? || delimiter
          open = quote == delimiter ? 0_u8 : delimiter
          depth = 0
          j = delimiter_at
        elsif byte == '/'.ord && regex_literal_start?(line, j)
          quote = byte
        elsif byte == '#'.ord
          break
        elsif byte == '<'.ord && j + 1 < size && line.byte_at(j + 1) == '<'.ord && operand_start?(line, j)
          k = j + 2
          indented = k < size && (line.byte_at(k) == '~'.ord || line.byte_at(k) == '-'.ord)
          k += 1 if indented
          id = nil
          if k < size && (line.byte_at(k) == '"'.ord || line.byte_at(k) == '\''.ord || line.byte_at(k) == '`'.ord)
            close = line.byte_index(line.byte_at(k), k + 1)
            if close && close > k + 1
              id = line.byte_slice(k + 1, close - k - 1)
              k = close + 1
            end
          elsif k < size && (line.byte_at(k).unsafe_chr.ascii_letter? || line.byte_at(k) == '_'.ord)
            start = k
            while k < size && (line.byte_at(k).unsafe_chr.ascii_alphanumeric? || line.byte_at(k) == '_'.ord)
              k += 1
            end
            id = line.byte_slice(start, k - start)
          end
          if id
            yield id, indented
            j = k
            next
          end
          j += 1
        end
        j += 1
      end
    end

    PERCENT_CLOSERS = {'('.ord.to_u8 => ')'.ord.to_u8, '['.ord.to_u8 => ']'.ord.to_u8,
                       '{'.ord.to_u8 => '}'.ord.to_u8, '<'.ord.to_u8 => '>'.ord.to_u8}

    # `<<` / `%` start a literal only where an operand can begin: at line
    # start or right after whitespace or an opening/operator byte, so
    # `1<<FLAGS` and `a%b` stay operators.
    private def self.operand_start?(line : String, index : Int32) : Bool
      index == 0 || " \t(,=[{|&!".includes?(line.byte_at(index - 1).unsafe_chr)
    end

    # Offset of the delimiter of a `%` literal starting at `index`
    # (`%(`, `%w[`, `%r{`, `%q|` …), or nil when `%` is the modulo operator.
    private def self.percent_literal_delimiter(line : String, index : Int32) : Int32?
      k = index + 1
      return if k >= line.bytesize
      k += 1 if "qQwWiIrsx".includes?(line.byte_at(k).unsafe_chr) && k + 1 < line.bytesize
      char = line.byte_at(k).unsafe_chr
      return if char.ascii_alphanumeric? || char.ascii_whitespace? || char == '=' || char == '_' || line.byte_at(k) >= 0x80
      k
    end

    # A `/` opens a regex literal when the previous non-blank byte cannot end
    # an operand (`x = /re/`, `foo(/re/)`, `s =~ /re/`); after a name or `)`
    # it is division.
    private def self.regex_literal_start?(line : String, index : Int32) : Bool
      k = index - 1
      while k >= 0 && line.byte_at(k).unsafe_chr.ascii_whitespace?
        k -= 1
      end
      k < 0 || "(,=[{|&!~;".includes?(line.byte_at(k).unsafe_chr)
    end

    # Line indices of every possible heredoc terminator, so finding the one
    # that closes an opener is a binary search rather than a forward scan
    # (a file of unterminated `<<X` lines would otherwise be quadratic).
    private class HeredocTerminators
      @indented : Hash(String, Array(Int32))? = nil
      @flush : Hash(String, Array(Int32))? = nil

      def initialize(@lines : Array(String))
      end

      # First line after `from` that closes heredoc `id`: the identifier
      # alone on the line, at column 0 unless the opener was `<<~`/`<<-`.
      def after(id : String, from : Int32, indented : Bool) : Int32?
        build unless @indented
        table = indented ? @indented : @flush
        candidates = table.try(&.[id]?)
        return unless candidates
        pos = candidates.bsearch_index { |line_index| line_index > from }
        pos ? candidates[pos] : nil
      end

      private def build
        indented = Hash(String, Array(Int32)).new
        flush = Hash(String, Array(Int32)).new
        @lines.each_with_index do |line, line_index|
          key = line.strip
          next if key.empty? || key.bytesize > 128
          (indented[key] ||= [] of Int32) << line_index
          (flush[key] ||= [] of Int32) << line_index if line.rstrip == key
        end
        @indented = indented
        @flush = flush
      end
    end

    protected def attach_ruby_callees(endpoint : Endpoint, callees : Array(Noir::RubyCalleeExtractor::Entry))
      Noir::RubyCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def attach_do_block_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      if block = extract_ruby_do_block(lines, index)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
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
