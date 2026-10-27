require "../../models/analyzer"
require "../../utils/char_offsets"
require "../../miniparsers/php_callee_extractor"
require "../../minilexers/php_lexer"
require "../../utils/utils.cr"

require "./file_scan_engine"

module Analyzer::Php
  abstract class PhpEngine < FileScanEngine
    # See AGENTS.md §"Two engine shapes" (and
    # docs/content/development/analyzer_architecture/) for when to override
    # `analyze_file` vs. `analyze` + `parallel_file_scan`.

    # Default source set for PHP framework adapters: every registered
    # `.php` file. Symfony overrides this to also include YAML route
    # configs (`.yaml` / `.yml`). Prefer the extension index over
    # walking the whole monorepo `file_map`.
    protected def php_source_files : Array(String)
      get_files_by_extension(".php")
    end

    # Extension + test-path filtering lives here so adapters don't
    # re-check every monorepo path. Paths come from CodeLocator (regular
    # files only); missing files error on read and are logged.
    protected def scan_target_files : Array(String)
      php_source_files
    end

    protected def scan_accepts?(path : String) : Bool
      !PhpEngine.test_path?(base_relative_path(path), root_docs: root_docs_skipped?)
    end

    # Whether a `docs/` tree at the scan base is skipped as runnable doc
    # snippets. True for framework adapters, where nothing under `docs/` is a
    # route; the plain PHP analyzer turns it off, because there a `docs/`
    # section is served like any other directory (`docs/index.php?page=…`).
    protected def root_docs_skipped? : Bool
      true
    end

    TEST_DIR_RE = %r{/(?:Tests|tests|Fixtures|workbench|legacy_tests)/|/Test/(?:Unit|Integration|Mftf|Integrity|Legacy|Fixture|_files)/|/test/phpunit/|/config/routes/test/}

    # Standard PHP test-source conventions:
    #
    #   * `/Tests/`               — PSR-4 / Symfony convention
    #     (`src/Symfony/Bundle/FrameworkBundle/Tests/...`)
    #   * `/tests/`               — Laravel / CakePHP / PHPUnit default
    #   * `/Test/Unit/`, `/Test/Mftf/`, … — Magento's per-module test trees
    #     (`Test/Unit/_files/webapi.xml`), `/test/phpunit/` — Dolibarr, and
    #     `/config/routes/test/` — Symfony's test-env routes. A bare
    #     `Test/` or `test/` is *not* a test dir: it is the `Test` namespace
    #     of `app/Http/Controllers/Test/` (Laravel), `src/Controller/Test/`
    #     (Symfony), a ThinkPHP `application/test/` or Yii `modules/test/`
    #     module, all real routes.
    #   * `/Fixtures/`, `/legacy_tests/` — test data and Dusk suites
    #   * `/workbench/`           — Orchestra Testbench skeleton app
    #   * `/docs/` at the scan base — runnable doc snippets
    #     (API Platform `docs/guides`); anchored, because Folio mounts
    #     `resources/views/docs` as a real route. `root_docs: false` drops
    #     it for the plain PHP analyzer, which serves a `docs/` section.
    #   * `*Test.php` filename    — PHPUnit suffix convention
    #   * `*Tests.php` filename   — pluralized variant (rare)
    #
    # symfony/symfony's own repo accounts for ~63 phantom endpoints
    # under `src/Symfony/Bundle/FrameworkBundle/Tests/...`. The
    # conventions are unambiguous — production routing never adopts
    # any of them.
    #
    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. The conventions describe a location inside
    # the project, so matching the absolute path handed the decision to
    # whatever directory the checkout happened to live in: the same tree
    # scanned from `~/work/tests/myapp` reported 0 endpoints instead of
    # 235.
    def self.test_path?(relative_path : String, root_docs : Bool = true) : Bool
      return true if relative_path.matches?(TEST_DIR_RE)
      return true if root_docs && relative_path.starts_with?("/docs/")
      base = File.basename(relative_path)
      return true if base.ends_with?("Test.php")
      base.ends_with?("Tests.php")
    end

    # `content` with comments blanked (docblocks kept), offsets and lines
    # intact — see `Noir::PhpLexer#without_comments`. Adapters that pull
    # routes out with regexes run them on this so commented-out routes stay
    # dead. Call it after the adapter's relevance gate: it lexes the file.
    protected def php_code(content : String) : String
      Noir::PhpLexer.new(content).without_comments
    end

    # Regex fragment for the rest of a call's argument list, up to the `)`
    # that closes it. Quoted strings are skipped whole so a `)` in one
    # (`'placeholder' => '(:num)'`) does not end the list; nested calls are
    # not balanced, so the text stops at their first bare `)`. Possessive
    # throughout, so it never backtracks.
    CALL_ARGS_TAIL = /(?:[^)'"]++|'(?:[^'\\]|\\.)*+'|"(?:[^"\\]|\\.)*+")*+/.source

    RESOURCE_FILTER_RE = /['"](only|except)['"]\s*=>\s*(?:['"]([^'"]*)['"]|(?:\[|array\s*\()([^\])]*))/i

    # Whether a resource action survives the call's `only`/`except` options,
    # given as `['index', 'show']`, `'index,show'` or `array('new')`.
    protected def resource_action_allowed?(args : String, action : String) : Bool
      args.scan(RESOURCE_FILTER_RE) do |m|
        names = if single = m[2]?
                  single.split(',').map(&.strip)
                else
                  m[3].scan(/['"]([^'"]+)['"]/).map(&.[1])
                end
        return false if names.includes?(action) == (m[1].downcase == "except")
      end
      true
    end

    # Find `'<key>' => [` within `[from, to)` and return the index of the `[`,
    # verified to be real code (not a comment / heredoc). Mautic's
    # `Config/config.php` and Nextcloud's `appinfo/routes.php` both declare
    # routes as keyed array literals.
    protected def find_key_array_open(content : String, lexer : Noir::PhpLexer, key : String, from : Int32, to : Int32) : Int32?
      regex = Regex.new("['\"]#{Regex.escape(key)}['\"]\\s*=>\\s*\\[")
      pos = from
      while match = content.match(regex, pos)
        match_text = match[0]
        start = content.index(match_text, pos)
        break unless start && start < to
        bracket_pos = start + match_text.size - 1
        # Validate the `[` (a code char) rather than the key's opening quote,
        # which the lexer masks as string content — so a real `'routes' => [`
        # passes while one buried in a heredoc/comment (masked `[`) is rejected.
        return bracket_pos if lexer.in_code?(bracket_pos)
        pos = start + match_text.size
      end
      nil
    end

    protected def php_base_path_for(path : String) : String
      configured_base_for(path)
    end

    # Directory (normalized) of the nearest `composer.json` above `path`, or
    # "" — the app a file belongs to in a monorepo.
    protected def composer_project_root(path : String) : String
      expanded = Noir::PathScope.expand(path)
      get_files_by_basename("composer.json").map { |f| Noir::PathScope.normalize_root(File.dirname(f)) }
        .select { |dir| Noir::PathScope.under_normalized_root?(expanded, dir) }.max_by?(&.size) || ""
    end

    # Short name (or alias) => FQCN for every `use` import in `content`.
    protected def parse_use_imports(content : String) : Hash(String, String)
      imports = {} of String => String

      # Plain imports: `use App\Http\Controllers\FooController;` (optional alias).
      content.scan(/(?:\A|[;\n{])\s*use\s+([A-Za-z_\\][\w\\]*)(?:\s+as\s+([A-Za-z_]\w*))?\s*;/) do |match|
        fqcn = match[1]
        short = match[2]? || fqcn.split('\\').last
        imports[short] = fqcn unless short.empty?
      end

      # Grouped imports: `use App\Http\Controllers\{FooController, BarController as Bar};`
      content.scan(/(?:\A|[;\n{])\s*use\s+([A-Za-z_\\][\w\\]*\\)\{([^}]+)\}/) do |match|
        prefix = match[1]
        match[2].split(',').each do |entry|
          item = entry.strip
          next if item.empty?
          next unless m = item.match(/\A([A-Za-z_\\][\w\\]*)(?:\s+as\s+([A-Za-z_]\w*))?\z/)
          fqcn = prefix + m[1]
          short = m[2]? || m[1].split('\\').last
          imports[short] = fqcn unless short.empty?
        end
      end

      imports
    end

    # `ref` as a fully-qualified class name, resolved through `imports` and
    # the file's `namespace` the way PHP resolves a class reference.
    protected def qualify_class(ref : String, imports : Hash(String, String), namespace : String?) : String
      return ref.lchop('\\') if ref.starts_with?('\\')
      head, _, rest = ref.partition('\\')
      if mapped = imports[head]?
        mapped = mapped.lchop('\\')
        return rest.empty? ? mapped : "#{mapped}\\#{rest}"
      end
      namespace ? "#{namespace}\\#{ref}" : ref
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
    INTERPOLATION_DOLLAR_BRACE_RE = /\$\{([A-Za-z_]\w*)\}/
    INTERPOLATION_BRACE_DOLLAR_RE = /\{\$([A-Za-z_]\w*)\}/
    INTERPOLATION_DOLLAR_RE       = /\$([A-Za-z_]\w*)/

    protected def normalize_php_interpolation(path : String) : String
      # Most route literals have no interpolation; skip three PCRE
      # gsub passes when `$` is absent.
      return path unless path.includes?('$')

      path = path.gsub(INTERPOLATION_DOLLAR_BRACE_RE) { |_| "{#{$~[1]}}" }
      path = path.gsub(INTERPOLATION_BRACE_DOLLAR_RE) { |_| "{#{$~[1]}}" }
      path = path.gsub(INTERPOLATION_DOLLAR_RE) { |_| "{#{$~[1]}}" }
      path
    end

    # Naive English singular of a resource name (`photos` -> `photo`,
    # `categories` -> `category`), for nested-resource parameter names.
    protected def singularize_resource_segment(segment : String) : String
      return segment[0...-3] + "y" if segment.ends_with?("ies") && segment.size > 3
      return segment[0...-2] if segment.ends_with?("ses") && segment.size > 3
      return segment[0...-1] if segment.ends_with?("s") && segment.size > 1
      segment
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

    protected def attach_method_callees(endpoint : Endpoint, method_body : Tuple(String, Int32)?, path : String)
      return unless method_body

      body, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, path, start_line)
      attach_php_callees(endpoint, callees)
    end

    # Body of an inline `function (...) use (...) { ... }` closure handler
    # starting at `pos`: `{body, position after the closure, body start line}`,
    # or `{nil, pos, nil}` when no closure starts there.
    INLINE_CLOSURE_HEAD_RE = /\G(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i

    # Char positions in and out, like the rest of the route loops, but every
    # step goes through `offsets`: this runs once per route, and the plain
    # `String` forms are O(file) per call on non-ASCII content.
    protected def extract_inline_closure_body(offsets : Noir::CharOffsets, pos : Int32, base_line : Int32) : Tuple(String?, Int32, Int32?)
      size = offsets.content.size
      return {nil, pos, nil} unless pos < size

      scan_pos = pos
      while offsets.ascii_whitespace?(scan_pos)
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < size

      match = offsets.match(INLINE_CLOSURE_HEAD_RE, scan_pos)
      return {nil, pos, nil} unless match

      close_byte = find_matching_php_close_brace_at_byte(offsets.content, match.byte_end(0) - 1)
      return {nil, pos, nil} unless close_byte

      brace_pos = offsets.end(match) - 1
      body_end = offsets.char(close_byte)
      body_start_line = base_line + offsets.line(brace_pos) - 1
      {offsets.slice(brace_pos + 1, body_end), body_end + 1, body_start_line}
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      while pos < content.size && content[pos].ascii_whitespace?
        pos += 1
      end
      pos
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

      body_start_line = line_number_for_index(content, brace_start)
      {content[(brace_start + 1)...method_end], body_start_line}
    end

    # Newlines strictly before `pos`, a CHAR offset — i.e. the 0-based line
    # index where `line_number_for_index` gives the 1-based number.
    #
    # Four analyzers (laravel, lumen, slim, thinkphp) each carried a
    # byte-identical `content[0...pos].count('\n')` copy of this. That form
    # allocates a prefix substring per call; routing through the inherited
    # helper drops the allocation and keeps one definition of "which line is
    # this offset on" for the whole engine.
    protected def newline_count_before(content : String, pos : Int32) : Int32
      line_number_for_index(content, pos) - 1
    end

    # Drop repeat `(param_type, name)` pairs, keeping the first.
    #
    # Was five byte-identical private copies (hyperf, laminas, lumen, slim,
    # thinkphp). The NUL separator matters: it cannot occur in either field,
    # so `("query", "a\0b")` and `("query\0a", "b")` cannot collide.
    protected def dedup_params(params : Array(Param)) : Array(Param)
      seen = Set(String).new
      params.select do |param|
        key = "#{param.param_type}\0#{param.name}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end

    # `Illuminate\Http\Request` reads (Laravel, Lumen): `$request->input('x')`,
    # `request()->query('x')`, `$request->header('X-Token')`, ... Capture 1 is
    # the accessor, capture 2 the input name.
    ILLUMINATE_ACCESSORS       = "input|post|get|query|header|cookie|file|hasFile|has|filled|string|integer|boolean|float|date|enum|array"
    ILLUMINATE_REQUEST_READ_RE = /(?:\$request|\brequest\(\s*\))\s*->\s*(#{ILLUMINATE_ACCESSORS})\s*\(\s*['"]([^'"]+)['"]/
    ILLUMINATE_READ_TYPES      = {"get" => "query", "query" => "query", "header" => "header", "cookie" => "cookie"}
    # Calls taking a validation rules array: `$request->validate([...])`,
    # `$this->validate($request, [...])`, `Validator::make($data, [...])`.
    ILLUMINATE_VALIDATE_RE = /(?:->\s*validate(?:WithBag)?|\bValidator::make)\s*\(/
    # A rules-array key: `'title' =>`, `'author.name' =>` (input `author`).
    RULE_KEY_RE = /['"]([\w-]+)(?:\.[^'"]*)?['"]\s*=>/

    # A dynamic property read, `$request->email`: `Request::__get` returns
    # that input. Not a call, not a chain, not an assignment, and not one of
    # the request's own public properties (`$request->query->get(...)`).
    ILLUMINATE_DYNAMIC_READ_RE    = /\$request\s*->\s*([a-z_]\w*)\b(?!\s*(?:\(|->|=(?![=>])))/
    ILLUMINATE_REQUEST_PROPERTIES = Set{"attributes", "request", "query", "server", "files", "cookies", "headers", "content", "json", "session"}

    # Where an accessor's input comes from; body inputs as "form".
    protected def illuminate_read_type(accessor : String) : String
      ILLUMINATE_READ_TYPES[accessor]? || "form"
    end

    # Input an `Illuminate\Http\Request` handler body reads: accessor calls,
    # dynamic properties and the keys of its validation rules. Body inputs
    # come back as "form". `klass`, the source of the class the body belongs
    # to, lets a rules argument that is not a literal (`$this->rules['update']`)
    # be read.
    protected def illuminate_request_params(body : String, klass : String? = nil) : Array(Param)
      params = [] of Param
      body.scan(ILLUMINATE_REQUEST_READ_RE) do |m|
        params << Param.new(m[2], "", illuminate_read_type(m[1]))
      end
      body.scan(ILLUMINATE_DYNAMIC_READ_RE) do |m|
        params << Param.new(m[1], "", "form") unless ILLUMINATE_REQUEST_PROPERTIES.includes?(m[1])
      end
      if klass && body.matches?(ILLUMINATE_CONST_READ_RE)
        body.scan(ILLUMINATE_CONST_READ_RE) do |m|
          klass.match(/\bconst\s+#{m[2]}\s*=\s*(['"])([^'"\\$]+)\1\s*;/).try { |c| params << Param.new(c[2], "", illuminate_read_type(m[1])) }
        end
      end
      params.concat(illuminate_loop_reads(body)) if body.includes?("foreach")
      params.concat(illuminate_paginator_reads(body)) if body.includes?("aginate")
      if body.matches?(ILLUMINATE_VALIDATE_RE)
        lexer = Noir::PhpLexer.new(body, php_mode: true)
        body.scan(ILLUMINATE_VALIDATE_RE) do |m|
          open = m.end(0) - 1
          next unless lexer.in_code?(open) && (close = lexer.matching_delimiter(open))
          # The rules are the first argument that reads as a rules array; a
          # later one is custom messages (keyed by rule name), an earlier one
          # the request or its data.
          top_level_args(lexer, body, open + 1, close).each do |arg|
            if rules = resolve_rules(arg, body, lexer, klass, 0)
              params.concat(rules)
              break
            end
          end
        end
      end
      dedup_params(params)
    end

    # `$request->has(self::ENTITY_KEY)`: the input named by a class constant.
    ILLUMINATE_CONST_READ_RE = /(?:\$request|\brequest\(\s*\))\s*->\s*(#{ILLUMINATE_ACCESSORS})\s*\(\s*(?:self|static)::([A-Z_][A-Z0-9_]*)\s*[,)]/
    # `->paginate(...)` / `simplePaginate` read the current page from the
    # request's `page` input, `cursorPaginate` its `cursor`.
    ILLUMINATE_PAGINATE_RE = /->\s*(paginate|simplePaginate|cursorPaginate)\s*\(/
    # `foreach ($fields as $field)` / `foreach (['a', 'b'] as $k => $field)`.
    ILLUMINATE_FOREACH_RE = /\bforeach\s*\(\s*(\$\w+|\[[^\[\]]*\])\s+as\s+(?:\$\w+\s*=>\s*)?\$(\w+)\s*\)\s*\{/
    STRING_LIST_RE        = /\A\s*(?:(['"])[\w.-]+\1\s*(?:,\s*|\z))+\z/

    # A paginator reads the request unless the call passes the page itself
    # (`paginate($perPage, $columns, $pageName, $page)`, cursor as 4th too);
    # a literal `$pageName` renames the input.
    private def illuminate_paginator_reads(body : String) : Array(Param)
      params = [] of Param
      lexer = Noir::PhpLexer.new(body, php_mode: true)
      body.scan(ILLUMINATE_PAGINATE_RE) do |m|
        open = m.end(0) - 1
        next unless lexer.in_code?(open) && (close = lexer.matching_delimiter(open))
        args = top_level_args(lexer, body, open + 1, close)
        next if args.size >= 4
        name = m[1] == "cursorPaginate" ? "cursor" : "page"
        if page_name = args[2]?
          next unless literal = page_name.match(/\A(['"])([\w.-]+)\1\z/)
          name = literal[2]
        end
        params << Param.new(name, "", "form")
      end
      params
    end

    # Input read in a loop over a literal list of names: `$fields = ['a',
    # 'b']; foreach ($fields as $field) { $request->input($field); }` reads
    # `a` and `b`. Only a list assigned once, of plain string names, and a
    # loop variable the body never reassigns.
    private def illuminate_loop_reads(body : String) : Array(Param)
      params = [] of Param
      lexer = Noir::PhpLexer.new(body, php_mode: true)
      body.scan(ILLUMINATE_FOREACH_RE) do |m|
        next unless lexer.in_code?(m.begin(0)) && (close = lexer.matching_delimiter(m.end(0) - 1))
        var = m[2]
        loop_body = body[m.end(0)...close]
        next if loop_body.matches?(/\$#{var}\s*(?:[.+\-*\/]|\?\?)?=(?![=>])/)
        reads = loop_body.scan(/(?:\$request|\brequest\(\s*\))\s*->\s*(#{ILLUMINATE_ACCESSORS})\s*\(\s*\$#{var}\s*[,)]/)
        next if reads.empty?
        list = m[1]
        if list.starts_with?('$')
          assigns = body.scan(/#{Regex.escape(list)}\b\s*(?:\[[^\]]*\]\s*)?=(?![=>])/)
          next unless assigns.size == 1 && (open = body.index('[', assigns[0].end(0))) && body[assigns[0].end(0)...open].blank?
          next unless list_close = lexer.matching_delimiter(open)
          list = body[open..list_close]
        end
        inner = list[1...-1]
        next unless inner.matches?(STRING_LIST_RE)
        names = inner.scan(/['"]([\w.-]+)['"]/).map(&.[1])
        reads.each { |read| names.each { |name| params << Param.new(name, "", illuminate_read_type(read[1])) } }
      end
      params
    end

    # The comma-separated arguments between `from` and `to` (exclusive).
    private def top_level_args(lexer : Noir::PhpLexer, source : String, from : Int32, to : Int32) : Array(String)
      args = [] of String
      pos = from
      while pos < to
        stop = Math.min(lexer.expression_end(pos), to)
        arg = source[pos...stop].strip
        args << arg unless arg.empty?
        pos = stop + 1
      end
      args
    end

    RULES_SUBSCRIPT_RE = /\A(.*?)\[\s*['"]([\w-]+)['"]\s*\]\z/m
    THIS_MEMBER_RE     = /\A\$this->(\w+)\s*(\(\s*\))?\z/
    LOCAL_VAR_RE       = /\A\$(\w+)\z/

    # Rule keys of a validate call's argument, read only where they are
    # literal: an array, `array_merge(...)` of such, a `$this->rules()`
    # method's returned array or `$this->rules` property initializer of the
    # same class, optionally subscripted (`$this->rules()['update']`), or a
    # local `$rules` assigned one of those (plus its `$rules['x'] = ...` keys).
    # nil when the argument is not a rules array.
    private def resolve_rules(expr : String, body : String, lexer : Noir::PhpLexer, klass : String?, depth : Int32) : Array(Param)?
      return if depth > 2
      expr = expr.strip
      return rule_key_params(expr) if expr.starts_with?('[')

      if merge = expr.match(/\Aarray_merge\s*\((.*)\)\z/m)
        inner = merge[1]
        merged = top_level_args(Noir::PhpLexer.new(inner, php_mode: true), inner, 0, inner.size)
          .compact_map { |arg| resolve_rules(arg, body, lexer, klass, depth + 1) }.flatten
        return merged.empty? ? nil : merged
      end

      key = nil
      if subscript = expr.match(RULES_SUBSCRIPT_RE)
        expr, key = subscript[1].strip, subscript[2]
      end

      if member = expr.match(THIS_MEMBER_RE)
        array = klass.try { |source| class_member_array(source, member[1], !member[2]?.nil?) }
        array = array_entry(array, key) if array && key
        return array.try { |text| rule_key_params(text) }
      end

      return unless key.nil? && (local = expr.match(LOCAL_VAR_RE))
      name = local[1]
      return if name == "this" || name == "request"
      params = [] of Param
      body.scan(/\$#{name}\s*=(?![=>])/) do |assign|
        next unless lexer.in_code?(assign.begin(0))
        value = body[assign.end(0)...lexer.expression_end(assign.end(0))]
        resolve_rules(value, body, lexer, klass, depth + 1).try { |found| params.concat(found) }
      end
      body.scan(/\$#{name}\[\s*['"]([\w-]+)['"]\s*\](?:\[\s*\])?\s*=(?![=>])/) do |entry|
        next unless lexer.in_code?(entry.begin(0))
        params << Param.new(entry[1], "", "form")
        value = body[entry.end(0)...lexer.expression_end(entry.end(0))]
        params << Param.new("#{entry[1]}_confirmation", "", "form") if value.matches?(/['"][^'"]*\bconfirmed\b/)
      end
      params.empty? ? nil : params
    end

    # The array literal a class's `name()` method returns, or its `$name`
    # property is initialized to.
    # ponytail: a `rules()` the class does not define is read as its `$rules`
    # property, the shape a base controller's `rules()` usually has; follow
    # the parent class if that ever misleads.
    private def class_member_array(klass : String, name : String, method : Bool) : String?
      if method && (sig = klass.match(/(?:public|protected|private)\s+(?:static\s+)?function\s+#{name}\s*\(/))
        return unless method_body = extract_php_method_body_after(klass, sig.begin(0))
        return unless ret = method_body[0].match(/\breturn\s+\[/)
        return literal_array_at(method_body[0], ret.end(0) - 1)
      end
      return unless prop = klass.match(/(?:public|protected|private|var)\s+(?:static\s+)?(?:\??[\w\\|]+\s+)?\$#{name}\s*=\s*\[/)
      literal_array_at(klass, prop.end(0) - 1)
    end

    private def literal_array_at(source : String, open : Int32) : String?
      close = Noir::PhpLexer.new(source, php_mode: true).matching_delimiter(open)
      source[open..close] if close
    end

    # The array value of `key` at the top level of an array literal.
    private def array_entry(array : String, key : String) : String?
      lexer = Noir::PhpLexer.new(array, php_mode: true)
      depth = 0
      last = 0
      array.scan(/['"]#{Regex.escape(key)}['"]\s*=>\s*(?=\[)/) do |m|
        (last...m.begin(0)).each do |i|
          case lexer.masked[i]
          when '[', '(' then depth += 1
          when ']', ')' then depth -= 1
          end
        end
        last = m.begin(0)
        next unless depth == 1 && lexer.in_code?(m.end(0))
        if close = lexer.matching_delimiter(m.end(0))
          return array[m.end(0)..close]
        end
      end
      nil
    end

    # `'password' => 'required|confirmed'`: Laravel's `confirmed` rule reads
    # a second input, `password_confirmation`.
    RULE_CONFIRMED_RE = /['"]([\w-]+)['"]\s*=>\s*(?:['"][^'"]*\bconfirmed\b|\[[^\]]*['"]confirmed['"])/

    # One "form" param per key of a validation rules array or `rules()` body.
    protected def rule_key_params(rules : String) : Array(Param)
      params = rules.scan(RULE_KEY_RE).map { |m| Param.new(m[1], "", "form") }
      rules.scan(RULE_CONFIRMED_RE) { |m| params << Param.new("#{m[1]}_confirmation", "", "form") }
      params
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
      start = content.char_index_to_byte_index(open_pos)
      return unless start
      close = find_matching_php_close_brace_at_byte(content, start)
      content.byte_index_to_char_index(close) if close
    end

    # BYTE-offset form of `find_matching_php_close_brace`: takes and returns
    # byte offsets, so a per-route caller pays no O(n) char/byte conversion.
    protected def find_matching_php_close_brace_at_byte(content : String, start : Int32) : Int32?
      bytes = content.to_slice
      return unless start < bytes.size && bytes[start] == BYTE_OPEN_BRACE

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
          return pos if depth == 0
        end

        pos += 1
      end

      nil
    end
  end
end
