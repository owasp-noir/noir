# Part of `GoAuthTagger`: a beego filter that authorizes every request
# against a Casbin policy.
#
#   web.InsertFilter("*", web.BeforeRouter, routers.ApiFilter)
#   func ApiFilter(ctx *context.Context) {
#       allowed, _ := authz.IsAllowed(subOwner, subName, method, urlPath, ...)
#       if !allowed { denyRequest(ctx) }          // "Unauthorized operation"
#   }
#   // authz: Enforcer.Enforce(...), policy loaded from a literal:
#   p, *, *, POST, /api/signup, *, *
#   p, *, *, GET, /api/get-account, *, *
#
# The filter is a guard when its body (or a function it calls, two hops)
# calls a Casbin `Enforce` and it denies under a negated test (`if
# !allowed {`) — what the deny branch writes (a 401/403, or an
# "unauthorized" / "forbidden" / "denied" message) is read off the block or
# a same-package function it calls. A policy found in the same Go module
# (a Go raw string or a `.csv` file of `p, ...` lines, read through the
# model's `[policy_definition]` when one is found) names the public paths:
# a line whose subject fields are all `*` (or `anonymous`) and whose other
# fields beyond method and path are `*`. Every other route the filter's
# pattern covers is guarded. Without a policy in the scan the filter is
# not read: the paths it lets through are unknown.
module GoBeegoCasbinFilter
  INSERT_FILTER     = /\b(?:web|beego)\s*\.\s*InsertFilter\s*\(\s*"([^"]*)"\s*,\s*[\w.]+\s*,\s*([\w.]+)\s*[,)]/
  CASBIN_ENFORCE    = /\.\s*Enforce(?:Ex|WithMatcher)?\s*\(/
  CASBIN_POLICY     = /^\s*p\s*,\s*(.+?)\s*$/
  POLICY_DEFINITION = /\[policy_definition\]\s*\n\s*p\s*=\s*([^\n]+)/
  RAW_STRING        = /`([^`]*)`/
  NEGATED_IF        = /\A(?:\}\s*else\s+)?if\s+!\s*\w+\s*\{\z/
  DENY_MESSAGE      = /unauthori[sz]ed|forbidden|denied|\bdeny/i
  # A log line names a denial without making one.
  LOG_LINE          = /\b(?:logs?|logger|slog|fmt)\s*\.\s*\w+\s*\(/i
  QUALIFIED_CALL    = /(?<![\w.])(\w+)\s*\.\s*(\w+)\s*\(/
  PLAIN_CALL        = /(?<![\w.])([A-Za-z_]\w*)\s*\(/
  ANONYMOUS_SUBJECT = %w[* anonymous]

  # One filter: the go module it is registered in, its pattern, the
  # public `{method, path regex, path}` rows of its policy, its tag.
  alias CasbinFilter = {module: String, pattern: String, public: Array({String, Regex, String}), tag: Tag}

  @casbin_filters : Array(CasbinFilter)? = nil
  # Package directories whose code calls `Enforce`.
  @enforcer_dirs = Set(String).new

  private def beego_casbin_guard(endpoint : Endpoint) : Tag?
    file = endpoint.details.code_paths.first?.try(&.path) || return
    url = endpoint.url
    mod = go_module(file)
    casbin_filters.each do |filter|
      next unless same_program?(filter[:module], mod) && beego_pattern_covers?(filter[:pattern], url)
      shaped = url.gsub(/:\w+|\{[^}\/]*\}/, "x")
      next if filter[:public].any? do |(method, path_re, path)|
                casbin_method?(method, endpoint.method) &&
                # ponytail: a granted path also covers what sits below it,
                # since the filter often folds sub-paths onto one policy
                # path (`/api/login/oauth/...` -> `/api/login/oauth`) before
                # it asks; a sub-path the filter does not fold reads open.
                (shaped.matches?(path_re) || shaped.starts_with?(path.rstrip('/') + "/"))
              end
      return filter[:tag]
    end
    nil
  end

  # `*`, the verb itself, or a `regexMatch` alternation (`(GET)|(POST)`).
  private def casbin_method?(policy : String, method : String) : Bool
    return true if policy == "*" || policy.upcase == method
    return false unless policy.includes?('|')
    method.matches?(Regex.new("\\A(?:#{policy})\\z", Regex::Options::IGNORE_CASE)) rescue false
  end

  private def casbin_filters : Array(CasbinFilter)
    @casbin_filters ||= begin
      filters = [] of CasbinFilter
      go_sources = collect_files_by_extension(".go").reject(&.ends_with?("_test.go"))
      go_sources.each do |file|
        content = read_file(file) || next
        next unless content.includes?("InsertFilter")
        code_only(content).scan(INSERT_FILTER) do |m|
          # code_only blanked the pattern: read it off the raw source.
          raw = content.scan(INSERT_FILTER).find { |r| r[2] == m[2] } || next
          filter = casbin_filter(raw[1], m[2], file, go_sources)
          filters << filter if filter
        end
      end
      filters
    end
  end

  private def casbin_filter(pattern : String, reference : String, file : String, go_sources : Array(String)) : CasbinFilter?
    qualifier, _, name = reference.rpartition('.')
    dirs = qualifier.empty? ? [File.dirname(file)] : package_dirs(qualifier, file)
    body = dirs.compact_map { |dir| @bodies.functions_for(dir)[name]? }.first? || return
    return unless reaches_enforcer?(body, 2) && denies_when_refused?(body)
    mod = go_module(file)
    policy = casbin_policy(mod, go_sources) || return
    rows, where = policy
    tag = Tag.new("auth", "Protected by beego filter #{reference}: its Casbin policy (#{where}) lets anonymous callers reach only the paths it grants to `*`; a policy loaded at runtime (a database adapter) can grant more", "go_auth")
    {module: mod, pattern: pattern, public: rows, tag: tag}
  end

  # `body` calls a Casbin `Enforce`, itself or through the functions it
  # calls, `hops` deep.
  private def reaches_enforcer?(body : Noir::GoCalleeExtractor::FunctionBody, hops : Int32) : Bool
    source = code_only(body.source)
    if source.matches?(CASBIN_ENFORCE)
      @enforcer_dirs << File.dirname(body.file_path)
      return true
    end
    return false if hops <= 0
    dir = File.dirname(body.file_path)
    source.scan(QUALIFIED_CALL).each do |call|
      package_dirs(call[1], body.file_path).each do |pkg|
        @bodies.functions_for(pkg)[call[2]]?.try { |callee| return true if reaches_enforcer?(callee, hops - 1) }
      end
    end
    source.lines.each_with_index do |line, idx|
      next if idx == 0
      line.scan(PLAIN_CALL).each do |call|
        @bodies.functions_for(dir)[call[1]]?.try { |callee| return true if callee != body && reaches_enforcer?(callee, hops - 1) }
      end
    end
    false
  end

  # An `if !allowed {` block that denies: a 401/403 or a deny message in
  # it, or in a same-package function it calls.
  private def denies_when_refused?(body : Noir::GoCalleeExtractor::FunctionBody) : Bool
    lines = body.source.lines
    dir = File.dirname(body.file_path)
    lines.each_with_index do |raw, idx|
      next unless code_only(raw).strip.matches?(NEGATED_IF)
      depth = 0
      (idx...lines.size).each do |i|
        code = code_only(lines[i])
        depth += code.count('{') - code.count('}')
        if i > idx && !lines[i].matches?(LOG_LINE)
          return true if denial?(lines[i])
          code.scan(PLAIN_CALL).each do |call|
            callee = @bodies.functions_for(dir)[call[1]]? || next
            return true if callee.source.lines.skip(1).any? { |line| !line.matches?(LOG_LINE) && denial?(line) }
          end
        end
        break if depth <= 0
      end
    end
    false
  end

  private def denial?(line : String) : Bool
    code_only(line).matches?(GoAuthTagger::REJECTS_REQUEST) || line.matches?(DENY_MESSAGE)
  end

  # The public rows of the first policy found in module `mod`, and where;
  # its fields are named by the first model definition that fits them.
  private def casbin_policy(mod : String, go_sources : Array(String)) : {Array({String, Regex, String}), String}?
    definitions = [] of Array(String)
    policies = [] of {Array(Array(String)), String}
    in_module = ->(file : String) { (owner = go_module(file)) == mod || owner.starts_with?(mod + "/") || same_program?(owner, mod) }
    # A policy file only when no Go literal holds one: `.csv` may be data.
    sources = go_sources.select(&.ends_with?(".go"))
    sources = collect_files_by_extension(".conf") + collect_files_by_extension(".csv") if sources.none? { |file| read_file(file).try(&.matches?(/^\s*p\s*,/m)) }
    sources.each do |file|
      next unless in_module.call(file)
      next if (File.size(file) rescue 0) > 1_000_000
      content = read_file(file) || next
      texts = file.ends_with?(".go") ? content.scan(RAW_STRING).map(&.[1]) : [content]
      texts.each do |text|
        text.match(POLICY_DEFINITION).try { |definition| definitions << definition[1].split(',').map(&.strip) }
        rows = text.lines.compact_map { |line| line.match(CASBIN_POLICY).try(&.[1].split(',').map(&.strip)) }
        policies << {rows, file} unless rows.empty?
      end
    end
    # The enforcer's own package first.
    rows, file = policies.find { |(_, path)| @enforcer_dirs.includes?(File.dirname(path)) } || policies.first? || return
    where = base_relative_path(file).lchop('/')
    # The model whose `p` has as many fields as the policy's lines and
    # names a field the lines fill with paths.
    width = rows.first.size
    definitions << %w[sub obj act] if width == 3
    layout = definitions.each do |names|
      next unless names.size == width
      path_col = names.index(&.matches?(/path|url/i)) || names.index { |n| n.downcase == "obj" } || next
      method_col = names.index(&.matches?(/method|\Aact/i)) || next
      break {names, path_col, method_col} if rows.count { |row| row[path_col]?.try(&.starts_with?('/')) } * 2 > rows.size
    end
    names, path_col, method_col = layout || return
    subjects = names.each_index.select { |i| names[i].downcase.starts_with?("sub") }.to_a
    public = rows.compact_map do |row|
      next unless row.size == names.size
      next unless subjects.all? { |i| ANONYMOUS_SUBJECT.includes?(row[i]) }
      next unless row.each_index.all? { |i| subjects.includes?(i) || i == path_col || i == method_col || row[i] == "*" }
      {row[method_col], key_match(row[path_col]), row[path_col]}
    end
    {public, where}
  end

  # beego filter patterns: `*` / `/*` everything, `/api/*` a subtree, any
  # other a single path (`:id` matching one segment).
  private def beego_pattern_covers?(pattern : String, url : String) : Bool
    return true if pattern == "*" || pattern == "/*"
    if pattern.ends_with?("/*")
      head = pattern.rchop("/*")
      return url == head || url.starts_with?(head + "/")
    end
    url.matches?(key_match(pattern))
  end

  # Casbin's `keyMatch2`: `*` matches anything, a `:name` segment one
  # segment.
  private def key_match(path : String) : Regex
    pattern = path.split('/').join('/') do |segment|
      segment.starts_with?(':') ? "[^/]+" : Regex.escape(segment).gsub("\\*", ".*")
    end
    Regex.new("\\A#{pattern}\\z")
  end
end
