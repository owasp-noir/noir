require "../../../analyzer/analyzers/python/python_helper"
require "../../../utils/top_level_split"

# A project middleware in `settings.MIDDLEWARE` that turns an
# unauthenticated request away (a login redirect, a 401/403) unless its
# path is exempt. It is judged by its definition: its `__call__` (or
# `process_request`) is walked for an anonymous caller at the endpoint's
# path and verb, and it guards the endpoint when every way through that
# serves the view needs a logged-in caller.
#
# Conditions evaluate to `T` / `F`, `Choice` (the caller decides: a query
# parameter, or a path test the endpoint's `<path:...>` placeholder may or
# may not satisfy) or `Unknown` (a setting, a test this cannot read). A
# view served only behind an `Unknown` keeps the guard, with a note.
module DjangoMiddlewareGuard
  private record MwStmt, text : String, children : Array(MwStmt)

  # A middleware class: the method walked, the lists its exemptions read
  # (`NO_AUTH = [...]`, a loop variable over one), the locals holding the
  # request path or the view's response, and the project root it serves.
  private record MwClass, name : String, root : String, body : Array(MwStmt),
    lists : Hash(String, Array(String)), path_vars : Array(String),
    response_vars : Array(String), process_request : Bool

  private record MwSample, path : String, static : String, open_ended : Bool, method : String

  enum MwTri
    T
    F
    Choice
    Unknown
  end

  enum MwOutcome
    Refuse
    Pass
    PassUnresolved
    Other
    Fall
    FallUnresolved
  end

  MW_IDENTITY       = /\b(?:is_authenticated|is_anonymous)\b/
  MW_LOGIN_REDIRECT = /\bHttpResponseRedirect\s*\(.*\b(?:log_?in|sign_?in)\b/i
  # What only a logged-in caller passes: `AnonymousUser` is never staff,
  # active or permitted, and a credential check fails without one.
  MW_ANONYMOUS_FAILS = /\buser\.(?:is_authenticated|is_staff|is_superuser|is_active)\b|\bhas_perms?\s*\(|\bauthenticate\s*\(|\b(?:headers|META|COOKIES|session)\b.*['"][\w-]*(?:key|token|auth|secret|signature|password)[\w-]*['"]/i
  MW_CALLER_INPUT    = /\brequest\.(?:GET|POST|COOKIES|headers|META|query_params|data|body|FILES|session)\b/
  MW_PATH_EXPR       = /(?<![\w.])request\.(?:path_info|path|get_full_path\(\s*\))(?:\[[^\]]*\])?/
  MW_STRING          = /\A[rRfFbBuU]{0,2}(['"])(.*)\1\z/

  @middlewares = [] of MwClass
  @settings_lists = Hash(String, Array(String)).new
  @middleware_guards = Hash({String, String, String}, String?).new

  # The project middleware classes a settings file lists in `MIDDLEWARE`.
  private def scan_middleware(settings_path : String, code : String)
    collect_lists(code, @settings_lists)
    root = nearest_project_root(settings_path, /\Amanage\.py\z/) || ""
    bracketed_values_after(code, DjangoAuthTagger::MIDDLEWARE_ASSIGNMENT).each do |value|
      value.scan(/['"]([A-Za-z_][\w.]*\.[A-Za-z_]\w*)['"]/) do |entry|
        dotted = entry[1]
        next if dotted.starts_with?("django.")
        next if @middlewares.any? { |known| known.name == dotted && known.root == root }
        if klass = middleware_class(dotted, root)
          @middlewares << klass
        end
      end
    end
  end

  private def middleware_class(dotted : String, root : String) : MwClass?
    mod, _, name = dotted.rpartition('.')
    rel = mod.gsub('.', '/')
    files = collect_files_by_extension(".py")
    module_file = files.find { |file| file.ends_with?("/#{rel}.py") || file.ends_with?("/#{rel}/__init__.py") } || return
    file, class_name = python_definition_site(module_file, name) || return
    lines = read_file_lines(file) || return
    class_re = /^class\s+#{Regex.escape(class_name)}\b/
    idx = lines.index(&.matches?(class_re)) || return
    {"__call__", "process_request"}.each do |method|
      body = method_body(lines, idx, method) || next
      body = body.gsub(PythonGuardDefinitions::DOCSTRING, "")
      next unless body.matches?(MW_IDENTITY) && mw_refusal?(body)
      lists = Hash(String, Array(String)).new
      collect_lists(lines.map { |line| Analyzer::Python::Helper.strip_python_comment(line) }.join('\n'), lists)
      collect_lists(body, lists)
      # A loop variable stands for every item of the list it walks.
      body.scan(/\bfor\s+(\w+)\s+in\s+((?:settings\.)?\w+)/) do |m|
        if items = mw_list(m[2], lists)
          lists[m[1]] = items
        end
      end
      path_vars = body.scan(/^\s*(\w+)\s*=\s*#{MW_PATH_EXPR.source}/m).map(&.[1])
      response_vars = body.scan(/^\s*(\w+)\s*=\s*(?:self\.)?get_response\s*\(/m).map(&.[1])
      return MwClass.new(class_name, root, mw_tree(body), lists, path_vars, response_vars, method == "process_request")
    end
    nil
  end

  # `NAME = [...]`, `NAME += [...]`, `NAME.append("...")` / `.extend([...])`:
  # the string literals each name may hold, wherever it is assigned.
  private def collect_lists(code : String, into : Hash(String, Array(String)))
    code.scan(/^[ \t]*([A-Za-z_]\w*)[ \t]*\+?=[ \t]*(?=[\[(])/m) do |m|
      if value = bracketed_after(code, /^[ \t]*#{m[1]}[ \t]*\+?=/m, m.begin)
        (into[m[1]] ||= [] of String).concat(mw_literals(value))
      end
    end
    code.scan(/\b([A-Za-z_]\w*)\.(?:append|extend|insert)\s*\(([^\n]*)\)/) do |m|
      next unless into.has_key?(m[1])
      into[m[1]].concat(mw_literals(m[2]))
    end
  end

  private def mw_literals(text : String) : Array(String)
    text.scan(/[rRfFbBuU]{0,2}(['"])((?:\\.|(?!\1).)*)\1/).map { |m| mw_unbrace(m[2]) }
  end

  # An f-string's `{...}` interpolation is the mount prefix
  # (`rf"^{re.escape(prefix)}/api/"`), not part of the path.
  private def mw_unbrace(literal : String) : String
    literal.gsub(/\{[^{}]*\}/, "")
  end

  private def mw_list(name : String, lists : Hash(String, Array(String))) : Array(String)?
    if setting = name.lchop?("settings.")
      @settings_lists[setting]?
    else
      lists[name]? || @settings_lists[name]?
    end
  end

  private def mw_refusal?(text : String) : Bool
    text.matches?(DjangoAuthTagger::DJANGO_REFUSAL) || text.matches?(PythonGuardDefinitions::FORBIDDEN) ||
      text.matches?(PythonGuardDefinitions::UNAUTHENTICATED) || text.matches?(PythonGuardDefinitions::LOGIN_REDIRECT) ||
      text.matches?(MW_LOGIN_REDIRECT)
  end

  # The guard the project middleware put on `endpoint`, or nil.
  private def middleware_guard(endpoint : Endpoint) : String?
    return if @middlewares.empty?
    file = endpoint.details.code_paths.first?.try(&.path) || return
    key = {file, endpoint.url, endpoint.method}
    return @middleware_guards[key] if @middleware_guards.has_key?(key)
    sample = mw_sample(endpoint.url, endpoint.method.upcase)
    guard = nil
    @middlewares.each do |klass|
      next unless Noir::PathScope.under_root?(file, klass.root)
      @mw_unresolved = @mw_last_unknown = nil
      outcomes = mw_block(klass.body, klass, sample, nil)
      if klass.process_request
        # Falling off `process_request` returns None: the view runs.
        outcomes << MwOutcome::Pass if outcomes.includes?(MwOutcome::Fall)
        if outcomes.includes?(MwOutcome::FallUnresolved)
          outcomes << MwOutcome::PassUnresolved
          @mw_unresolved ||= @mw_fall_why
        end
      end
      next if !outcomes.includes?(MwOutcome::Refuse) || outcomes.includes?(MwOutcome::Pass)
      guard = if outcomes.includes?(MwOutcome::PassUnresolved)
                "Protected by #{klass.name} (settings.MIDDLEWARE; whether it lets the request through depends on `#{@mw_unresolved.try(&.[0, 80])}`, which this cannot tell)"
              else
                "Protected by #{klass.name} (settings.MIDDLEWARE refuses unauthenticated requests outside its exempt paths)"
              end
      break
    end
    @middleware_guards[key] = guard
  end

  @mw_unresolved : String? = nil

  # The endpoint's path with each placeholder filled in, and, when one of
  # them is `<path:...>`, the fixed text before it.
  private def mw_sample(url : String, method : String) : MwSample
    open = /<path:\w+>|\(\?P<\w+>\.[*+]\??\)/
    fill = ->(text : String) do
      text.gsub(open, "x/x").gsub(/<int:\w+>|\{\w+\}|\(\?P<\w+>\\d[^)]*\)/, "1").gsub(/<(?:\w+:)?\w+>|\(\?P<\w+>[^)]*\)/, "x")
    end
    if at = url.index(open)
      MwSample.new(fill.call(url), fill.call(url[0, at]), true, method)
    else
      MwSample.new(fill.call(url), "", false, method)
    end
  end

  # Logical statements by indent: continuation lines joined, comments
  # dropped, an inline block (`if x: return y`) split off.
  private def mw_tree(body : String) : Array(MwStmt)
    entries = [] of {Int32, String}
    pending = ""
    pending_indent = 0
    depth = 0
    body.each_line do |raw|
      line = Analyzer::Python::Helper.strip_python_comment(raw).rstrip
      next if line.strip.empty? && depth == 0
      if depth == 0
        pending_indent = line.size - line.lstrip.size
        pending = line.strip
      else
        pending += " " + line.strip
      end
      depth = mw_mask(pending)[1]
      next if depth > 0 || pending.ends_with?('\\')
      entries << {pending_indent, pending}
      pending = ""
    end
    root = [] of MwStmt
    stack = [{-1, root}]
    entries.each do |indent, text|
      while stack.last[0] >= indent
        stack.pop
      end
      head, inline = mw_split_inline(text)
      stmt = MwStmt.new(head, [] of MwStmt)
      stmt.children << MwStmt.new(inline, [] of MwStmt) if inline
      stack.last[1] << stmt
      stack << {indent, stmt.children}
    end
    root
  end

  BLOCK_KEYWORD = /\A(?:if|elif|else|for|while|with|try|except|finally|async\s+with|async\s+for)\b/

  private def mw_split_inline(text : String) : {String, String?}
    return {text, nil} unless text.matches?(BLOCK_KEYWORD)
    masked = mw_mask(text)[0]
    colon = masked.index(/:(?!=)/) || return {text, nil}
    rest = text[(colon + 1)..].strip
    rest.empty? ? {text, nil} : {text[0..colon], rest}
  end

  # `text` with string contents and bracketed text blanked out (the
  # brackets themselves kept), and the bracket depth at its end.
  private def mw_mask(text : String) : {String, Int32}
    depth = 0
    quote = nil
    escaped = false
    masked = String.build do |io|
      text.each_char do |char|
        if q = quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == q
            quote = nil
            io << (depth > 0 ? '_' : char)
            next
          end
          io << '_'
          next
        end
        case char
        when '\'', '"'
          quote = char
          io << (depth > 0 ? '_' : char)
        when '(', '[', '{'
          io << (depth > 0 ? '_' : char)
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
          io << (depth > 0 ? '_' : char)
        else
          io << (depth > 0 ? '_' : char)
        end
      end
    end
    {masked, depth}
  end

  # The outcomes reachable for an anonymous caller running `stmts`. `why`
  # is the condition this cannot tell that reaching them depends on.
  private def mw_block(stmts : Array(MwStmt), klass : MwClass, sample : MwSample, why : String?) : Set(MwOutcome)
    outcomes = Set(MwOutcome).new
    idx = 0
    while idx < stmts.size
      stmt = stmts[idx]
      text = stmt.text
      idx += 1
      if text.starts_with?("if ")
        chain = [stmt]
        while idx < stmts.size && stmts[idx].text.matches?(/\A(?:elif\b|else\s*:)/)
          chain << stmts[idx]
          idx += 1
        end
        branches = [] of {MwTri, Set(MwOutcome)}
        guessed = nil
        chain.each do |branch|
          value = MwTri::T
          cond = nil
          unless branch.text.starts_with?("else")
            cond = branch.text.sub(/\A(?:if|elif)\s+/, "").rchop(':').strip
            value = mw_eval(cond, klass, sample)
          end
          next if value.f?
          guessed = @mw_last_unknown = cond if value.unknown?
          outs = mw_block(branch.children, klass, sample, why)
          if value.unknown? && outs.includes?(MwOutcome::Pass)
            # Served only on a condition this cannot tell.
            @mw_unresolved ||= cond
            outs = outs.map { |outcome| outcome.pass? ? MwOutcome::PassUnresolved : outcome }.to_set
          end
          outcomes.concat(outs.reject { |outcome| mw_fall?(outcome) })
          branches << {value, outs}
          break if value.t?
        end
        reached = mw_chain_fall(branches, 0)
        return outcomes if reached == 0
        why ||= guessed if reached == 1
      elsif text.matches?(/\A(?:async\s+)?with\b/)
        inner = mw_block(stmt.children, klass, sample, why)
        outcomes.concat(inner.reject { |outcome| mw_fall?(outcome) })
        reached = mw_fall_state(inner)
        return outcomes if reached == 0
        why ||= @mw_last_unknown if reached == 1
      elsif text.matches?(BLOCK_KEYWORD)
        # Loops and `try` / `except` blocks may run or not.
        outcomes.concat(mw_block(stmt.children, klass, sample, why).reject { |outcome| mw_fall?(outcome) })
      elsif text.matches?(/\A(?:async\s+)?(?:def|class)\b/)
        next
      elsif text.starts_with?("return") && !text.matches?(/\Areturn\w/)
        outcomes << mw_return(text.lchop("return").strip, klass, why)
        return outcomes
      elsif text.starts_with?("raise ")
        outcomes << (mw_refusal?(text) ? MwOutcome::Refuse : MwOutcome::Other)
        return outcomes
      end
    end
    # The outermost block finishes last: its value is what falling off
    # the method depends on.
    @mw_fall_why = why
    outcomes << (why ? MwOutcome::FallUnresolved : MwOutcome::Fall)
    outcomes
  end

  @mw_last_unknown : String? = nil
  @mw_fall_why : String? = nil

  private def mw_fall?(outcome : MwOutcome) : Bool
    outcome.fall? || outcome.fall_unresolved?
  end

  # Whether the statement after a block runs: 2 surely, 1 only on a
  # condition this cannot tell, 0 never.
  private def mw_fall_state(outs : Set(MwOutcome)) : Int32
    return 2 if outs.includes?(MwOutcome::Fall)
    outs.includes?(MwOutcome::FallUnresolved) ? 1 : 0
  end

  # The same for an `if` / `elif` / `else` chain from branch `idx` on:
  # the caller picks a `Choice` branch, and an `Unknown` one is sure only
  # when both of its ways fall through.
  private def mw_chain_fall(branches : Array({MwTri, Set(MwOutcome)}), idx : Int32) : Int32
    value, outs = branches[idx]? || return 2
    taken = mw_fall_state(outs)
    return taken if value.t?
    rest = mw_chain_fall(branches, idx + 1)
    return {taken, rest}.max if value.choice?
    return 2 if taken == 2 && rest == 2
    taken > 0 || rest > 0 ? 1 : 0
  end

  private def mw_return(expr : String, klass : MwClass, why : String?) : MwOutcome
    passes = expr.matches?(/\bget_response\s*\(|\bsuper\s*\(\s*\)\s*\.__call__\s*\(/) || klass.response_vars.includes?(expr) ||
             (klass.process_request && (expr.empty? || expr == "None"))
    if passes
      return MwOutcome::Pass unless why
      @mw_unresolved ||= why
      return MwOutcome::PassUnresolved
    end
    mw_refusal?("return #{expr}") ? MwOutcome::Refuse : MwOutcome::Other
  end

  # Python's `or` / `and` / `not` over the atoms below, `or` binding
  # loosest; grouping parentheses are stripped first.
  private def mw_eval(cond : String, klass : MwClass, sample : MwSample) : MwTri
    cond = cond.strip
    while cond.starts_with?('(') && (masked = mw_mask(cond)[0]) && masked.index(')') == cond.size - 1
      cond = cond[1...-1].strip
    end
    masked = mw_mask(cond)[0]
    {/\s+or\s+/, /\s+and\s+/}.each_with_index do |word, kind|
      parts = mw_split(cond, masked, word)
      next if parts.size < 2
      values = parts.map { |part| mw_eval(part, klass, sample) }
      return kind == 0 ? mw_or(values) : mw_and(values)
    end
    if masked.matches?(/\Anot\s/)
      return mw_not(mw_eval(cond[4..], klass, sample))
    end
    if m = masked.match(/\A\w+\s*:=/)
      return mw_eval(cond[m.end..], klass, sample)
    end
    mw_atom(cond, klass, sample)
  end

  private def mw_split(text : String, masked : String, word : Regex) : Array(String)
    parts = [] of String
    start = 0
    masked.scan(word) do |m|
      parts << text[start...m.begin]
      start = m.end
    end
    parts << text[start..]
  end

  private def mw_or(values : Array(MwTri)) : MwTri
    return MwTri::T if values.any?(&.t?)
    return MwTri::Choice if values.any?(&.choice?)
    values.all?(&.f?) ? MwTri::F : MwTri::Unknown
  end

  private def mw_and(values : Array(MwTri)) : MwTri
    return MwTri::F if values.any?(&.f?)
    return MwTri::Unknown if values.any?(&.unknown?)
    values.all?(&.t?) ? MwTri::T : MwTri::Choice
  end

  private def mw_not(value : MwTri) : MwTri
    case value
    when .t? then MwTri::F
    when .f? then MwTri::T
    else          value
    end
  end

  private def mw_atom(atom : String, klass : MwClass, sample : MwSample) : MwTri
    case atom
    when "True"                   then return MwTri::T
    when "False", "None"          then return MwTri::F
    when /\buser\.is_anonymous\b/ then return MwTri::T
    when MW_ANONYMOUS_FAILS       then return MwTri::F
    end
    # `any(request.path.startswith(url) for url in EXEMPT)`: the loop
    # variable already stands for the list.
    if generator = atom.match(/\Aany\s*\((.+)\s+for\s+\w+\s+in\s+[\w.]+\s*\)\z/m)
      return mw_eval(generator[1], klass, sample)
    end
    if m = atom.match(/\Arequest\.method(?:\.upper\(\))?\s*(==|!=|not\s+in|in)\s*(.+)\z/)
      verbs = mw_literals(m[2]).map(&.upcase)
      return MwTri::Unknown if verbs.empty?
      hit = verbs.includes?(sample.method)
      return (m[1] == "==" || m[1] == "in") == hit ? MwTri::T : MwTri::F
    end
    path = path_expr(klass)
    return mw_path_atom(atom, path, klass, sample) if atom.matches?(path)
    atom.matches?(MW_CALLER_INPUT) ? MwTri::Choice : MwTri::Unknown
  end

  private def path_expr(klass : MwClass) : Regex
    return MW_PATH_EXPR if klass.path_vars.empty?
    mw_re("#{MW_PATH_EXPR.source}|(?<![\\w.])(?:#{klass.path_vars.map { |var| Regex.escape(var) }.join('|')})\\b")
  end

  # A test of the request path: `.startswith(...)` / `.endswith(...)`,
  # `re.match` / `re.search` / `re.fullmatch`, `in` / `==`.
  private def mw_path_atom(atom : String, path : Regex, klass : MwClass, sample : MwSample) : MwTri
    p = "(?:#{path.source})"
    if m = atom.match(mw_re("\\A#{p}\\.(startswith|endswith)\\s*\\((.*)\\)\\z"))
      kind = m[1]
      values = mw_values(m[2], klass) || return MwTri::Unknown
      return mw_any(values) { |value| kind == "startswith" ? mw_prefix(sample, value) : mw_suffix(sample, value) }
    end
    if m = atom.match(/\Are\.(match|search|fullmatch)\s*\((.*)\)\z/)
      kind = m[1]
      args = Noir::TopLevelSplit.split(m[2], ',', Noir::TopLevelSplit::Rules::PYTHON)
      return MwTri::Unknown unless args.size >= 2 && args[1].strip.matches?(mw_re("\\A#{p}\\z"))
      values = mw_values(args[0], klass) || return MwTri::Unknown
      return mw_any(values) { |value| mw_regex(sample, value, kind) }
    end
    if m = atom.match(mw_re("\\A#{p}\\s*(==|!=|not\\s+in|in)\\s*(.+)\\z"))
      op, other = m[1], m[2]
    elsif m = atom.match(mw_re("\\A(.+?)\\s*(==|!=)\\s*#{p}\\z"))
      op, other = m[2], m[1]
    else
      return MwTri::Unknown
    end
    values = mw_values(other, klass) || return MwTri::Unknown
    hit = mw_any(values) { |value| mw_equal(sample, value) }
    op == "==" || op == "in" ? hit : mw_not(hit)
  end

  @mw_regexes = Hash(String, Regex).new

  private def mw_re(source : String) : Regex
    @mw_regexes[source] ||= Regex.new(source)
  end

  # The strings an argument stands for: literals, a list, a loop variable
  # over one, and their `+` concatenations. A leading name this cannot
  # read is taken for a mount prefix (`prefix + "/api/"`); nil when any
  # other part is unreadable.
  private def mw_values(expr : String, klass : MwClass) : Array(String)?
    expr = expr.strip
    if expr.matches?(/\A[(\[]/) && (inner = expr[1...-1]?)
      return mw_literals(inner)
    end
    parts = Noir::TopLevelSplit.split(expr, '+', Noir::TopLevelSplit::Rules::PYTHON).map(&.strip)
    results = [""]
    parts.each_with_index do |part, idx|
      choices = if m = part.match(MW_STRING)
                  [mw_unbrace(m[2])]
                elsif part.matches?(/\A(?:settings\.)?\w+\z/) && (items = mw_list(part, klass.lists))
                  items
                elsif idx == 0 && parts.size > 1
                  [""]
                else
                  return
                end
      results = results.flat_map { |head| choices.map { |tail| head + tail } }
      return if results.size > 512
    end
    results
  end

  private def mw_any(values : Array(String), & : String -> MwTri) : MwTri
    found = MwTri::F
    values.each do |value|
      verdict = yield value
      return verdict if verdict.t? || verdict.unknown?
      found = verdict if verdict.choice?
    end
    found
  end

  private def mw_prefix(sample : MwSample, value : String) : MwTri
    return MwTri::T if sample.path.starts_with?(value)
    sample.open_ended && value.starts_with?(sample.static) ? MwTri::Choice : MwTri::F
  end

  private def mw_suffix(sample : MwSample, value : String) : MwTri
    return MwTri::T if sample.path.ends_with?(value)
    sample.open_ended ? MwTri::Choice : MwTri::F
  end

  private def mw_equal(sample : MwSample, value : String) : MwTri
    return MwTri::T if sample.path == value
    sample.open_ended && value.starts_with?(sample.static) ? MwTri::Choice : MwTri::F
  end

  # ponytail: a `<path:...>` endpoint counts as possibly matching any
  # pattern; matching the pattern against its fixed prefix would sharpen it.
  private def mw_regex(sample : MwSample, value : String, kind : String) : MwTri
    source = case kind
             when "match"     then "\\A(?:#{value})"
             when "fullmatch" then "\\A(?:#{value})\\z"
             else                  value
             end
    regex = Regex.new(source) rescue return MwTri::Unknown
    return MwTri::T if sample.path.matches?(regex)
    sample.open_ended ? MwTri::Choice : MwTri::F
  end
end
