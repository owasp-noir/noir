require "../../models/analyzer"
require "../../miniparsers/php_callee_extractor"
require "../../utils/utils.cr"

module Analyzer::Php
  abstract class PhpEngine < Analyzer
    # See AGENTS.md §"Two engine shapes" (and
    # docs/content/development/analyzer_architecture/) for when to override
    # `analyze_file` vs. `analyze` + `parallel_file_scan`.

    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # Walk the project tree concurrently and invoke the block for each
    # readable, non-directory file. PHP analyzers apply their own
    # extension/pathname filters inside the block because Symfony matches
    # `.php` *and* YAML route files, Laravel checks `routes/*.php`, etc.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          next if PhpEngine.test_path?(path)

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

    # Standard PHP test-source conventions:
    #
    #   * `/Tests/`               — PSR-4 / Symfony convention
    #     (`src/Symfony/Bundle/FrameworkBundle/Tests/...`)
    #   * `/tests/`               — Laravel / CakePHP / PHPUnit default
    #   * `*Test.php` filename    — PHPUnit suffix convention
    #   * `*Tests.php` filename   — pluralized variant (rare)
    #
    # symfony/symfony's own repo accounts for ~63 phantom endpoints
    # under `src/Symfony/Bundle/FrameworkBundle/Tests/...`. The
    # conventions are unambiguous — production routing never adopts
    # any of them.
    def self.test_path?(path : String) : Bool
      return true if path.includes?("/Tests/")
      return true if path.includes?("/tests/")
      base = File.basename(path)
      return true if base.ends_with?("Test.php")
      base.ends_with?("Tests.php")
    end

    protected def php_base_path_for(path : String) : String
      configured_base_for(path)
    end

    # Route composition helper. Will migrate to a PHP route extractor when that
    # layer is introduced; kept here for now so Laravel/CakePHP/Symfony stop
    # duplicating it.
    protected def build_full_path(prefix : String, path : String) : String
      prefix = normalize_php_interpolation(prefix)
      path = normalize_php_interpolation(path)

      return prefix if path == "/" && !prefix.empty?
      return path if prefix.empty?

      full_path = "/#{prefix.strip('/')}/#{path.strip('/')}"
      full_path = full_path.gsub(/\/+/, "/")
      full_path = full_path.chomp('/') if full_path.size > 1
      full_path
    end

    # PHP double-quoted strings interpolate `$var`, `{$var}`, and
    # `${var}`. The route extractor captures the literal characters
    # between the quotes, so `"/api/{$VERSION}/items"` came out as
    # `/api/{$VERSION}/items` with the `$` leaking into the URL.
    # Rewrite each shape to `{name}` so the path-parameter
    # extractor picks it up and the URL template reads cleanly.
    # Same posture as the Python f-string and Ruby `#{}` fixes.
    protected def normalize_php_interpolation(path : String) : String
      path = path.gsub(/\$\{([A-Za-z_]\w*)\}/) { |_| "{#{$~[1]}}" }
      path = path.gsub(/\{\$([A-Za-z_]\w*)\}/) { |_| "{#{$~[1]}}" }
      path = path.gsub(/\$([A-Za-z_]\w*)/) { |_| "{#{$~[1]}}" }
      path
    end

    protected def extract_brace_path_params(route_path : String) : Array(Param)
      params = [] of Param
      route_path.scan(/\{(\w+)\??\}/).each do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    protected def attach_php_callees(endpoint : Endpoint, callees : Array(Noir::PhpCalleeExtractor::Entry))
      Noir::PhpCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_php_method_body_after(content : String, start_pos : Int32) : Tuple(String, Int32)?
      return unless start_pos < content.size

      context = content[start_pos..]
      func_match = context.match(/(?:public|protected|private)\s+(?:static\s+)?function\s+\w+[^{]*\{/m)
      return unless func_match

      func_start = context.index(func_match[0])
      return unless func_start

      brace_start = start_pos + func_start + func_match[0].size - 1
      method_end = find_matching_php_close_brace(content, brace_start)
      return unless method_end
      return if method_end <= brace_start + 1

      body_start_line = php_line_number_for_index(content, brace_start)
      {content[(brace_start + 1)...method_end], body_start_line}
    end

    protected def php_line_number_for_index(content : String, index : Int32) : Int32
      return 1 if index <= 0

      content[0...index].count('\n') + 1
    end

    # ASCII byte values for the structural delimiters scanned below.
    # All are < 0x80, so they can never collide with a UTF-8 multi-byte
    # continuation/lead byte (>= 0x80) — see `find_matching_php_close_brace`.
    private BYTE_NEWLINE     = '\n'.ord.to_u8
    private BYTE_STAR        = '*'.ord.to_u8
    private BYTE_SLASH       = '/'.ord.to_u8
    private BYTE_HASH        = '#'.ord.to_u8
    private BYTE_BACKSLASH   = '\\'.ord.to_u8
    private BYTE_DQUOTE      = '"'.ord.to_u8
    private BYTE_SQUOTE      = '\''.ord.to_u8
    private BYTE_OPEN_BRACE  = '{'.ord.to_u8
    private BYTE_CLOSE_BRACE = '}'.ord.to_u8

    # Find the `}` that closes the `{` at `open_pos`, skipping braces inside
    # strings and comments.
    #
    # Scans the raw byte buffer for O(1) positional access instead of
    # `String#[](Int)`, which is O(n) on strings containing multi-byte
    # characters and turned this loop into O(n^2). CJK-commented PHP (e.g.
    # CRMEB's Chinese docblocks) made noir hang for minutes per large
    # controller; byte scanning keeps it linear. Every delimiter we look for
    # is ASCII, and UTF-8 only uses bytes >= 0x80 for multi-byte sequences,
    # so a Chinese character can never be mistaken for a quote or brace.
    #
    # NOTE: a heredoc/nowdoc-aware, fully shared replacement lives in
    # `Noir::PhpLexer` (see the Laravel analyzer). Analyzers that call this in
    # a loop should migrate to building one `PhpLexer` per file and reusing
    # `matching_delimiter` — constructing a lexer per call re-lexes the whole
    # file and is ~hundreds of times slower on method-heavy controllers.
    protected def find_matching_php_close_brace(content : String, open_pos : Int32) : Int32?
      bytes = content.to_slice
      start = content.char_index_to_byte_index(open_pos)
      return unless start && start < bytes.size && bytes[start] == BYTE_OPEN_BRACE

      depth = 0
      in_string = false
      in_line_comment = false
      in_block_comment = false
      escaped = false
      quote = 0_u8
      pos = start
      size = bytes.size

      while pos < size
        char = bytes[pos]
        next_char = pos + 1 < size ? bytes[pos + 1] : 0_u8

        if in_line_comment
          in_line_comment = false if char == BYTE_NEWLINE
        elsif in_block_comment
          if char == BYTE_STAR && next_char == BYTE_SLASH
            in_block_comment = false
            pos += 1
          end
        elsif in_string
          if escaped
            escaped = false
          elsif char == BYTE_BACKSLASH
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == BYTE_SLASH && next_char == BYTE_SLASH
          in_line_comment = true
          pos += 1
        elsif char == BYTE_SLASH && next_char == BYTE_STAR
          in_block_comment = true
          pos += 1
        elsif char == BYTE_HASH
          in_line_comment = true
        elsif char == BYTE_DQUOTE || char == BYTE_SQUOTE
          in_string = true
          quote = char
        elsif char == BYTE_OPEN_BRACE
          depth += 1
        elsif char == BYTE_CLOSE_BRACE
          depth -= 1
          return content.byte_index_to_char_index(pos) if depth == 0
        end

        pos += 1
      end

      nil
    end
  end
end
