require "../../../analyzer/analyzers/python/python_helper"

# Judging a Python decorator by what its definition does: the Flask and
# Django auth taggers both read a project decorator's body (and the
# functions it calls) to decide whether it turns an unauthenticated caller
# away, and fall back to a name list only for a library decorator the scan
# does not hold. The including tagger supplies `decorator_description`.
module PythonGuardDefinitions
  DECORATOR_NAME = /^@([A-Za-z_][\w.]*)/
  TOP_LEVEL_DEF  = /^(?:async\s+)?def\s+(\w+)/
  # A function a body calls, or a decorator it applies to a nested `def`.
  CALLEE    = /@([A-Za-z_]\w*)|(?<![\w.])([A-Za-z_]\w*)\s*\(/
  DOCSTRING = /"""[\s\S]*?"""|'''[\s\S]*?'''/

  # What makes a decorator definition an auth guard: it answers 401 in any
  # spelling, or it reads a credential off the request and turns the request
  # away (Dify's inner-API key check answers 404), or it reads the logged-in
  # caller and denies with 403. A 403 alone is not enough: Dify's
  # `email_password_login_enabled` aborts 403 on a feature flag, which says
  # nothing about the caller.
  UNAUTHENTICATED    = /\braise\s+(?:\w+\.)*\w*(?:Unauthori[sz]ed|Unauthenticated|NotAuthenticated|AuthenticationFailed)(?:Error|Exception)?\b|\babort\s*\(\s*(?:401\b|(?:\w+\.)*UNAUTHORIZED\b)|\.unauthorized\s*\(|\.response_401\s*\(|\bverify_jwt_in_request\s*\((?=\s*(?:\)|[A-Za-z_]\w*\s*=))(?![^)]*\boptional\s*=\s*(?!False\b))|\breturn\b.*,\s*401\b|\bstatus(?:_code)?\s*=\s*401\b|\bHTTP_401_UNAUTHORIZED\b/
  REQUEST_CREDENTIAL = /\brequest\.(?:authorization\b|(?:headers|cookies|args)(?:\.get\s*\(|\[)\s*["'][\w-]*(?:key|token|auth|secret|signature|password|session)[\w-]*["'])/i
  REJECTION          = /\braise\s+[A-Za-z_]|\babort\s*\(|\breturn\b.*,\s*4\d\d\b/
  CALLER_IDENTITY    = /\bcurrent_user\b|\bis_authenticated\b|\bg\.user\b/
  FORBIDDEN          = /\braise\s+(?:\w+\.)*\w*(?:Forbidden|PermissionDenied|AccessDenied)\w*\b|\babort\s*\(\s*(?:403\b|(?:\w+\.)*FORBIDDEN\b)|\breturn\b.*,\s*403\b|\.response_403\s*\(/

  # Sending the caller to the login page is how a browser view refuses
  # an anonymous one.
  LOGIN_REDIRECT = /\bredirect\s*\(.*\b(?:log_?in|sign_?in)\b/i
  # Flask keeps the logged-in user in `session`; a helper such as
  # `authed()` reads it there.
  SESSION_READ = /(?<![\w.])session\s*(?:\.get\s*\(|\[)/
  # A wrapper calling the view it decorates.
  VIEW_CALL = /(?<![\w.])\w+\s*\(\s*\*\w+\s*,\s*\*\*\w+\s*\)/
  # The view called from a function wrapper or a method one (`f(self, *args, **kwargs)`).
  ANY_VIEW_CALL = /(?<![\w.])\w+\s*\(\s*(?:\w+\s*,\s*)?\*\w+\s*,\s*\*\*\w+\s*\)/
  # A condition that holds when its subject is absent or does not match.
  NEGATED_TEST = /\A\s*not\b|\bis\s+None\b|==\s*None\b|\bis\s+False\b|==\s*False\b|\bnot\s+in\b|!=/

  @python_defs = Hash(String, Hash(String, String)).new
  @verdicts = Hash(Tuple(String, String), Bool).new
  @identity_defs = Hash(Tuple(String, String, Int32), Bool).new
  @view_access = Hash(Tuple(String, String), ViewAccess).new

  # The guard a decorator line names, judged by the decorator's definition
  # when the scan has it, by its name only when it does not (a library
  # decorator such as flask-login's `login_required`).
  private def decorator_guard(line : String, file : String) : String?
    name = line.match(DECORATOR_NAME).try(&.[1]) || return
    target = resolve_def(file, name)
    return decorator_description(line, file) unless target
    verdict = @verdicts[target]?
    verdict = @verdicts[target] = guard_definition?(target[0], target[1], 0) if verdict.nil?
    return unless verdict
    # Settings are read at run time, so whether the open path is the
    # deployment's is not known here: report the guard and say so.
    view_access(target[0], target[1]).configurable? ? "#{name} (a setting can make it public)" : name
  end

  # Whether a definition body turns an unauthenticated caller away.
  private def refuses_caller?(body : String) : Bool
    body.matches?(UNAUTHENTICATED) ||
      (body.matches?(REQUEST_CREDENTIAL) && body.matches?(REJECTION)) ||
      (body.matches?(CALLER_IDENTITY) && body.matches?(FORBIDDEN))
  end

  # Whether `def name` in `file` turns an unauthenticated caller away, in
  # its own body or in a function it calls, up to two calls deep: Dify's
  # `validate_jwt_token` rejects inside `decode_jwt_token`,
  # `console_account_admission` returns `login_required(...)` of the view,
  # and `_api_prerequisite` stacks `@login_required` on its inner wrapper.
  #
  # A wrapper (a body that calls the view with `*args, **kwargs`) that
  # reads the caller and refuses with 403 or a login redirect is judged by
  # the paths that reach the view instead: it guards when every such path
  # needs an identified caller, or every one but those a setting opens
  # (`view_access`), or when it answers 401 / checks a request credential
  # regardless.
  private def guard_definition?(file : String, name : String, hops : Int32) : Bool
    body = without_view_error_handlers(python_defs(file)[name])
    if body.matches?(VIEW_CALL) && (body.matches?(FORBIDDEN) || body.matches?(LOGIN_REDIRECT)) &&
       identity_read?(body, file, 0)
      access = view_access(file, name)
      return true if access.closed? || access.configurable? || body.matches?(UNAUTHENTICATED) ||
                     (body.matches?(REQUEST_CREDENTIAL) && body.matches?(REJECTION))
    elsif refuses_caller?(body)
      return true
    end
    return false if hops >= 2
    body.scan(CALLEE).map { |m| m[1]? || m[2] }.uniq!.any? do |callee|
      next false if callee == name
      target = resolve_def(file, callee)
      !!target && guard_definition?(target[0], target[1], hops + 1)
    end
  end

  # `body` without the `except` clauses of a `try:` that calls the view:
  # Superset's `@api` answers 401 there for a `NoAuthorizationError` the
  # view raised, which translates a refusal made elsewhere rather than
  # making one.
  private def without_view_error_handlers(body : String) : String
    return body unless body.includes?("except") && body.matches?(ANY_VIEW_CALL)
    lines = body.lines
    kept = [] of String
    idx = 0
    while idx < lines.size
      line = lines[idx]
      kept << line
      idx += 1
      next unless line.strip == "try:"
      indent = line.size - line.lstrip.size
      block_end = block_end(lines, idx, indent)
      kept.concat(lines[idx...block_end])
      calls_view = lines[idx...block_end].any?(&.matches?(ANY_VIEW_CALL))
      idx = block_end
      while calls_view && idx < lines.size && lines[idx].size - lines[idx].lstrip.size == indent && lines[idx].lstrip.starts_with?("except")
        idx = block_end(lines, idx + 1, indent)
      end
    end
    kept.join('\n')
  end

  # The index past the block that starts at `idx`, under a header at `indent`.
  private def block_end(lines : Array(String), idx : Int32, indent : Int32) : Int32
    while idx < lines.size && (lines[idx].blank? || lines[idx].size - lines[idx].lstrip.size > indent)
      idx += 1
    end
    idx
  end

  # Whether `text` reads who the caller is: `current_user` / `g.user`, the
  # Flask `session`, a local assigned from one, or a function that does,
  # up to two calls deep (CTFd's `authed()` returns
  # `bool(session.get("id"))`).
  private def identity_read?(text : String, file : String, hops : Int32,
                             locals : Hash(String, String)? = nil) : Bool
    return true if text.matches?(CALLER_IDENTITY) || text.matches?(SESSION_READ)
    if locals
      text.scan(/(?<![\w.])[A-Za-z_]\w*/) do |m|
        expr = locals[m[0]]?
        return true if expr && identity_read?(expr, file, hops)
      end
    end
    return false if hops >= 2
    text.scan(CALLEE).any? do |m|
      target = resolve_def(file, m[1]? || m[2]) || next false
      key = {target[0], target[1], hops + 1}
      cached = @identity_defs[key]?
      if cached.nil?
        @identity_defs[key] = false # cycle guard
        cached = @identity_defs[key] = identity_read?(python_defs(target[0])[target[1]], target[0], hops + 1)
      end
      cached
    end
  end

  # How wrapper `def name` in `file` lets a caller who is not identified
  # reach the view, judged by the conditions above each view call: the enclosing `if` / `elif` / `else` branches and the earlier
  # sibling `if`s that refuse. CTFd's `require_verified_emails` calls the
  # view whenever email verification is off and never asks who the caller
  # is, so it is not a guard. `check_score_visibility` calls it when the
  # visibility setting is public and otherwise only for a logged-in caller
  # or an admin: a guard that a setting can lift. A view call under no condition is not
  # judged (the refusal may sit in a helper it calls), and a condition on
  # the decorator's own parameters is the call site's choice
  # (`admission(roles=...)`), not the caller's.
  enum ViewAccess
    # Every judged path to the view needs an identified caller.
    Closed
    # A path needs none, on conditions that do not read the caller, and
    # no other path needs one.
    Setting
    # A setting opens a path; every other judged path needs an identified
    # caller.
    Configurable
    # A path needs none although its conditions read the caller.
    Caller
  end

  private def view_access(file : String, name : String) : ViewAccess
    @view_access[{file, name}] ||= scan_view_access(file, name)
  end

  private def scan_view_access(file : String, name : String) : ViewAccess
    body = python_defs(file)[name]? || return ViewAccess::Closed
    lines = body.lines
    sig_end, params = signature(lines)
    locals = Hash(String, String).new
    lines.each do |line|
      if m = line.match(/^\s*([A-Za-z_]\w*)\s*=(?!=)\s*(.+)/)
        locals[m[1]] ||= m[2]
      end
    end
    open = closed = false
    lines.each_with_index do |line, idx|
      next if idx <= sig_end || !line.matches?(VIEW_CALL) || line.matches?(/^\s*(?:async\s+)?def\b/)
      gates = view_path_conditions(lines, idx, sig_end).map do |alternatives|
        alternatives.flat_map { |alternative| combine_paths(alternative.map { |cond, positive| branch_paths(cond, positive) }) }
      end
      # Each path that reaches the view is judged on its own: past
      # `if is_setup() and not is_admin(): abort(403)` one path needs only
      # the setting off and the other an admin caller.
      combine_paths(gates).each do |conditions|
        judged = conditions.compact_map do |cond, positive|
          implies_identity?(cond, positive, file, locals, params)
        end
        next if judged.empty?
        next closed = true if judged.includes?(true)
        # An open path on what the caller sends (`request.method == "GET"`)
        # is the caller's to take, not a setting.
        return ViewAccess::Caller if conditions.any? { |cond, _| identity_read?(cond, file, 0, locals) || cond.matches?(REQUEST_READ) }
        open = true
      end
    end
    return ViewAccess::Closed unless open
    closed ? ViewAccess::Configurable : ViewAccess::Setting
  rescue TooManyPaths
    ViewAccess::Caller
  end

  alias PathCondition = Tuple(String, Bool)
  REFUSAL_LINE   = /\A(?:return|raise)\b|\babort\s*\(/
  REQUEST_READ   = /(?<![\w.])request\./
  MAX_VIEW_PATHS = 32

  # More ways to the view than `MAX_VIEW_PATHS`: the wrapper is not judged.
  class TooManyPaths < Exception
  end

  # The gates line `idx` of a body runs under. A gate lists the ways past
  # it, each a set of conditions that hold together with whether each is
  # reached on its true branch.
  private def view_path_conditions(lines : Array(String), idx : Int32, sig_end : Int32) : Array(Array(Array(PathCondition)))
    found = [] of Array(Array(PathCondition))
    threshold = lines[idx].size - lines[idx].lstrip.size
    block = [] of String
    # An if/elif/else chain above the view at its own indent, last branch
    # first, each with its body.
    chain = [] of Tuple(String?, Array(String))
    j = idx - 1
    while j > sig_end
      line = lines[j]
      j -= 1
      next if line.blank?
      indent = line.size - line.lstrip.size
      stripped = line.strip
      if indent > threshold
        block << line
        next
      end
      if indent == threshold
        body = block.reverse
        block.clear
        if m = stripped.match(/\A(if|elif)\s+(.*?):?\z/)
          chain << {m[2], body}
          if m[1] == "if"
            gate = chain_gate(chain.reverse)
            found << gate if gate
            chain.clear
          end
        elsif stripped.matches?(/\Aelse\s*:/)
          chain << {nil, body}
        else
          chain.clear
        end
        next
      end
      break if stripped.matches?(/\A(?:async\s+)?def\b/)
      if m = stripped.match(/\A(?:if|elif|while)\s+(.*?):?\z/)
        found << [[{m[1], true}]]
      end
      if stripped.starts_with?("elif") || stripped.starts_with?("else")
        # The earlier branches of the chain did not hold.
        k = j
        while k > sig_end
          prior = lines[k]
          k -= 1
          next if prior.blank? || prior.size - prior.lstrip.size > indent
          break if prior.size - prior.lstrip.size < indent
          m = prior.strip.match(/\A(if|elif)\s+(.*?):?\z/) || break
          found << [[{m[2], false}]]
          break if m[1] == "if"
        end
      end
      threshold = indent
      block.clear
      chain.clear
    end
    found
  end

  # The ways past an if/elif/else chain one of whose branches refuses:
  # through each branch that does not (its own test holding, the earlier
  # ones failing), through a refusing one past checks nested in it, and
  # past the whole chain when it has no `else`. nil when no branch refuses.
  private def chain_gate(branches : Array(Tuple(String?, Array(String)))) : Array(Array(PathCondition))?
    refusing = branches.map { |branch| branch[1].any?(&.strip.matches?(REFUSAL_LINE)) }
    return unless refusing.includes?(true)
    gate = [] of Array(PathCondition)
    priors = [] of PathCondition
    branches.each_with_index do |branch, i|
      cond = branch[0]
      entry = cond ? priors + [{cond, true}] : priors.dup
      if !refusing[i]
        gate << entry
      elsif through = through_paths(branch[1])
        through.each { |inner| gate << entry + inner }
      end
      priors << {cond, false} if cond
    end
    gate << priors if branches.last[0]
    gate
  end

  # The ways through a refusing `block` without reaching its refusal, when
  # every refusal sits under an `if` nested in it (`if is_setup():` /
  # `if not is_admin(): abort(403)`); nil when it refuses outright or in a
  # shape not judged.
  private def through_paths(block : Array(String)) : Array(Array(PathCondition))?
    body_indent = block.min_of { |line| line.size - line.lstrip.size }
    inner = [] of Array(Array(PathCondition))
    block.each_with_index do |line, i|
      next unless line.size - line.lstrip.size == body_indent
      stripped = line.strip
      return if stripped.matches?(REFUSAL_LINE)
      next unless stripped.ends_with?(':')
      m = stripped.match(/\Aif\s+(.*?):\z/) || return
      sub = block[(i + 1)..].take_while { |part| part.size - part.lstrip.size > body_indent }
      next unless sub.any?(&.strip.matches?(REFUSAL_LINE))
      alternatives = [[{m[1], false}]]
      through_paths(sub).try &.each { |path| alternatives << [{m[1], true}] + path }
      inner << alternatives
    end
    return if inner.empty?
    combine_paths(inner)
  end

  # `a and b` failing, or `a or b` holding, is one path per operand.
  # Grouping parentheses are not parsed, as in `implies_identity?`.
  private def branch_paths(cond : String, positive : Bool) : Array(Array(PathCondition))
    unless cond.matches?(/(?:\A|[^\w\].'"])\s*\(/)
      disjuncts = cond.split(/\s+or\s+/)
      return disjuncts.map { |part| [{part, true}] } if positive && disjuncts.size > 1
      conjuncts = cond.split(/\s+and\s+/)
      return conjuncts.map { |part| [{part, false}] } if !positive && disjuncts.size == 1 && conjuncts.size > 1
    end
    [[{cond, positive}]]
  end

  # Every way through `gates` in turn, one alternative from each.
  private def combine_paths(gates : Array(Array(Array(PathCondition)))) : Array(Array(PathCondition))
    gates.reduce([[] of PathCondition]) do |paths, alternatives|
      combined = paths.flat_map { |path| alternatives.map { |alternative| path + alternative } }
      raise TooManyPaths.new if combined.size > MAX_VIEW_PATHS
      combined
    end
  end

  CONDITION_WORDS = %w[not is None True False in and or]

  # Whether reaching the true (`positive`) or false branch of `cond` needs
  # an identified caller; nil when `cond` tests only the decorator's own
  # parameters. `a or b` holding needs only one of them, so each must be
  # an identity test; `a or b` failing needs each to fail, so one is
  # enough (`and` the other way round). Grouping parentheses are not
  # parsed: such a condition is not judged.
  private def implies_identity?(cond : String, positive : Bool, file : String,
                                locals : Hash(String, String), params : Array(String)) : Bool?
    return if cond.matches?(/(?:\A|[^\w\].'"])\s*\(/)
    disjuncts = cond.split(/\s+or\s+/)
    if disjuncts.size > 1
      parts = disjuncts.compact_map { |part| implies_identity?(part, positive, file, locals, params) }
      return if parts.empty?
      return positive ? parts.all? : parts.includes?(true)
    end
    conjuncts = cond.split(/\s+and\s+/)
    if conjuncts.size > 1
      parts = conjuncts.compact_map { |part| implies_identity?(part, positive, file, locals, params) }
      return if parts.empty?
      return positive ? parts.includes?(true) : parts.all?
    end
    words = cond.scan(/[A-Za-z_]\w*/).map(&.[0]).reject(&.in?(CONDITION_WORDS))
    return if words.all?(&.in?(params))
    return false unless identity_read?(cond, file, 0, locals)
    negated = !cond.matches?(/\bis\s+not\s+None\b|!=\s*None\b/) && cond.matches?(NEGATED_TEST)
    positive ? !negated : negated
  end

  # The index of the line closing a `def`'s parameter list (`lines[0]` is
  # the `def`), and the parameter names, annotations and defaults dropped.
  private def signature(lines : Array(String)) : Tuple(Int32, Array(String))
    text = String::Builder.new
    depth = 0
    opened = false
    lines.each_with_index do |line, idx|
      line.each_char do |char|
        if char == '('
          text << char if opened && depth > 0
          opened = true
          depth += 1
        elsif char == ')' && opened
          depth -= 1
          if depth == 0
            # Brackets in annotations (`Callable[[A, B], R]`) hold commas too.
            params = text.to_s
            while params.includes?('[')
              stripped = params.gsub(/\[[^\[\]]*\]/, "")
              break if stripped == params
              params = stripped
            end
            names = params.gsub(/\([^()]*\)/, "").split(',').compact_map(&.strip.lstrip('*').match(/\A[A-Za-z_]\w*/).try(&.[0]))
            return {idx, names}
          end
          text << char
        elsif opened
          text << char
        end
      end
    end
    {0, [] of String}
  end

  private def resolve_def(file : String, name : String) : Tuple(String, String)?
    resolve(file, name) { |path, def_name| python_defs(path).has_key?(def_name) }
  end

  # `name` (`x` or `mod.x`) as used in `file`: `file` itself when it
  # declares it, else the module it is imported from, through package
  # re-exports (`from controllers.common.rbac import enforce_rbac_checks`
  # names the package `__init__.py`, which imports it from `checks.py`);
  # nil when the scan holds no declaration.
  private def resolve(file : String, name : String, & : String, String -> Bool) : Tuple(String, String)?
    mod, _, leaf = name.rpartition('.')
    return {file, leaf} if mod.empty? && yield file, leaf
    imports = python_imported_symbols(file)
    target = mod.empty? ? imports[leaf]? : imports[mod]?.try { |module_file| {module_file[0], leaf} if module_file[1].empty? }
    3.times do
      return if target.nil? || target[1].empty?
      return target if yield target[0], target[1]
      target = python_imported_symbols(target[0])[target[1]]?
    end
    nil
  end

  # Top-level `def` bodies of `path` by name, comments and docstrings
  # dropped. `@overload` stubs share their implementation's name, so a
  # name's bodies are joined.
  private def python_defs(path : String) : Hash(String, String)
    @python_defs[path] ||= begin
      bodies = Hash(String, String::Builder).new
      name = nil
      (read_file_lines(path) || [] of String).each do |line|
        if m = line.match(TOP_LEVEL_DEF)
          name = m[1]
        elsif !line.blank? && !line[0].ascii_whitespace? && !line[0].in?(')', ']')
          name = nil
        end
        if current = name
          (bodies[current] ||= String::Builder.new) << Analyzer::Python::Helper.strip_python_comment(line) << '\n'
        end
      end
      bodies.transform_values(&.to_s.gsub(DOCSTRING, ""))
    end
  end
end
