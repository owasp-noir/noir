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
  UNAUTHENTICATED    = /\braise\s+(?:\w+\.)*\w*(?:Unauthori[sz]ed|Unauthenticated|NotAuthenticated|AuthenticationFailed)(?:Error|Exception)?\b|\babort\s*\(\s*(?:401\b|(?:\w+\.)*UNAUTHORIZED\b)|\.unauthorized\s*\(|\breturn\b.*,\s*401\b|\bstatus(?:_code)?\s*=\s*401\b|\bHTTP_401_UNAUTHORIZED\b/
  REQUEST_CREDENTIAL = /\brequest\.(?:authorization\b|(?:headers|cookies|args)(?:\.get\s*\(|\[)\s*["'][\w-]*(?:key|token|auth|secret|signature|password|session)[\w-]*["'])/i
  REJECTION          = /\braise\s+[A-Za-z_]|\babort\s*\(|\breturn\b.*,\s*4\d\d\b/
  CALLER_IDENTITY    = /\bcurrent_user\b|\bis_authenticated\b|\bg\.user\b/
  FORBIDDEN          = /\braise\s+(?:\w+\.)*\w*(?:Forbidden|PermissionDenied|AccessDenied)\w*\b|\babort\s*\(\s*(?:403\b|(?:\w+\.)*FORBIDDEN\b)|\breturn\b.*,\s*403\b/

  @python_defs = Hash(String, Hash(String, String)).new
  @verdicts = Hash(Tuple(String, String), Bool).new

  # The guard a decorator line names, judged by the decorator's definition
  # when the scan has it, by its name only when it does not (a library
  # decorator such as flask-login's `login_required`).
  private def decorator_guard(line : String, file : String) : String?
    name = line.match(DECORATOR_NAME).try(&.[1]) || return
    target = resolve_def(file, name)
    return decorator_description(line) unless target
    verdict = @verdicts[target]?
    verdict = @verdicts[target] = guard_definition?(target[0], target[1], 0) if verdict.nil?
    name if verdict
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
  private def guard_definition?(file : String, name : String, hops : Int32) : Bool
    body = python_defs(file)[name]
    return true if refuses_caller?(body)
    return false if hops >= 2
    body.scan(CALLEE).map { |m| m[1]? || m[2] }.uniq!.any? do |callee|
      next false if callee == name
      target = resolve_def(file, callee)
      !!target && guard_definition?(target[0], target[1], hops + 1)
    end
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
