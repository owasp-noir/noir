# Part of `GoAuthTagger`: a beego filter that authorizes every request
# against a Casbin policy.
#
#   web.InsertFilter("*", web.BeforeRouter, routers.ApiFilter)
#   func ApiFilter(ctx *context.Context) {
#       allowed, _ := authz.IsAllowed(getSubject(ctx), urlPath, ...)
#       if !allowed { denyRequest(ctx) }       // ctx.Output.JSON(...)
#   }
#   func getSubject(ctx) string { if user == "" { return "anonymous" } ... }
#   // authz: Enforcer.Enforce(...), policy loaded from a literal:
#   p, *, POST, /api/signup
#
# A filter counts only when all of these hold:
#
# * it runs before the controller (`BeforeStatic`, `BeforeRouter`,
#   `BeforeExec`), registered by a live (uncommented) `InsertFilter`; each
#   registration keeps its own pattern;
# * its body (or a function it calls, two hops) calls a Casbin `Enforce`;
# * it writes a response under a negated test (`if !allowed {`): a 401/403,
#   or an `Output` / `ResponseWriter` write or `Abort`, in the block or in a
#   same-package function it calls (two hops) — a flag or a comment is not
#   a refusal;
# * an anonymous caller reaches that test: no earlier `if token == "" {
#   return }` in the filter lets a request without a credential through.
#
# The policy is a Go raw string (or, when no raw string holds one, a `.csv`
# / `.conf` file) of `p, ...` lines in the same Go module, read through the
# model definition whose path field the lines fill with paths. Its effect
# must be the plain allow-override (`some(where (p.eft == allow))`); a
# `deny` row grants nothing, and any other effect leaves the filter unread.
# A line grants anonymous access when every subject field is `*`, the
# subject the filter passes for a caller without a session (`return
# "anonymous"` / `user = "guest"` under an absence test), or a role that
# subject has through `g` lines, and its other fields are `*`. A path is
# compared with keyMatch2 after the folds the filter itself applies
# (`if strings.HasPrefix(p, "/scim") { return "/scim" }`). Every other route
# under the filter's pattern, in a program whose `main` package registers
# the filter (or imports the package that does), is guarded.
module GoBeegoCasbinFilter
  INSERT_FILTER     = /\b(?:web|beego)\s*\.\s*InsertFilter\s*\(\s*"([^"]*)"\s*,\s*([\w.]+)\s*,\s*([\w.]+)\s*[,)]/
  GUARD_POSITIONS   = %w[BeforeStatic BeforeRouter BeforeExec]
  CASBIN_ENFORCE    = /\.\s*Enforce(?:Ex|WithMatcher)?\s*\(/
  CASBIN_POLICY     = /^\s*p\s*,\s*(.+?)\s*$/
  CASBIN_ROLE       = /^\s*g\s*,\s*(.+?)\s*$/
  POLICY_DEFINITION = /\[policy_definition\]\s*\n\s*p\s*=\s*([^\n]+)/
  POLICY_EFFECT     = /\[policy_effect\]\s*\n\s*e\s*=\s*([^\n]+)/
  ALLOW_OVERRIDE    = "some(where(p.eft==allow))"
  RAW_STRING        = /`([^`]*)`/
  NEGATED_IF        = /\A(?:\}\s*else\s+)?if\s+!\s*\w+\s*\{\z/
  IF_HEAD           = /\A(?:\}\s*else\s+)?if\s+(?:[^;{]*;\s*)?(.+?)\s*\{\z/
  # A request with no credential: `!ok`, `token == ""`, `u == nil`, `len(t) == 0`.
  ABSENT_VALUE = /\A(?:!\s*\w+|\w+\s*==\s*(?:""|nil)|len\(\s*\w+\s*\)\s*==\s*0)\z/
  # A response written: beego's `ctx.Output` / `ResponseWriter`, an abort.
  RESPONSE_WRITE = /\.\s*(?:Output\s*\.\s*(?:SetStatus|JSON|JSONP|XML|YAML|Body|Download)|ResponseWriter\s*\.\s*(?:WriteHeader|Write)|Abort|CustomAbort|WriteString|Redirect|ServeJSON)\s*\(/
  PASS_ON        = /\A(?:return\b|[\w.]+\.Next\(\))/
  HAS_PREFIX     = /strings\s*\.\s*HasPrefix\s*\(\s*\w+\s*,\s*"([^"]+)"\s*\)/
  FOLD_TARGET    = /(?:return|\w+\s*=)\s*"([^"]+)"/
  QUALIFIED_CALL = /(?<![\w.])(\w+)\s*\.\s*(\w+)\s*\(/
  PLAIN_CALL     = /(?<![\w.])([A-Za-z_]\w*)\s*\(/
  STRING_VALUE   = /"([^"\\]*)"/
  PACKAGE_MAIN   = /^package\s+main\b/m

  # One filter: the package directories of the programs it runs in, its
  # pattern, the public `{method, path regex}` rows of its policy, the path
  # folds it applies, its tag.
  alias CasbinFilter = {dirs: Set(String), pattern: String, public: Array({String, Regex}), folds: Array({String, String}), tag: Tag}

  @casbin_filters : Array(CasbinFilter)? = nil
  # Package directories whose code calls `Enforce`.
  @enforcer_dirs = Set(String).new

  private def beego_casbin_guard(endpoint : Endpoint) : Tag?
    file = endpoint.details.code_paths.first?.try(&.path) || return
    url = endpoint.url
    dir = File.dirname(file)
    casbin_filters.each do |filter|
      next unless filter[:dirs].includes?(dir) && beego_pattern_covers?(filter[:pattern], url)
      shaped = url.gsub(/:\w+|\{[^}\/]*\}/, "x")
      if fold = filter[:folds].find { |(prefix, _)| shaped.starts_with?(prefix) }
        shaped = fold[1]
      end
      next if filter[:public].any? { |(method, path_re)| casbin_method?(method, endpoint.method) && shaped.matches?(path_re) }
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
      # One read per filter function; each registration adds its pattern.
      read = Hash({String, String}, CasbinFilter?).new
      go_sources = collect_files_by_extension(".go").reject(&.ends_with?("_test.go"))
      go_sources.each do |file|
        content = read_file(file) || next
        next unless content.includes?("InsertFilter")
        # Comments blanked, strings kept: each live registration with its
        # own pattern.
        Noir::CComments.strip(content, quotes: %("'), raw_quotes: "`").scan(INSERT_FILTER) do |m|
          next unless GUARD_POSITIONS.includes?(m[2].rpartition('.')[2])
          filter = read.put_if_absent({m[3], file}) { casbin_filter("", m[3], file, go_sources) }
          filters << filter.merge(pattern: m[1]) if filter
        end
      end
      filters
    end
  end

  private def casbin_filter(pattern : String, reference : String, file : String, go_sources : Array(String)) : CasbinFilter?
    qualifier, _, name = reference.rpartition('.')
    dirs = qualifier.empty? ? [File.dirname(file)] : package_dirs(qualifier, file)
    body = dirs.compact_map { |dir| @bodies.functions_for(dir)[name]? }.first? || return
    return unless reaches_enforcer?(body, 2) && anonymous_refused?(body)
    helpers = reachable_helpers(body, 2)
    policy = casbin_policy(go_module(file), go_sources, anonymous_subjects(body, helpers)) || return
    rows, where = policy
    folds = path_folds([body] + helpers)
    tag = Tag.new("auth", "Protected by beego filter #{reference}: its Casbin policy (#{where}) lets anonymous callers reach only the paths it grants them; a policy loaded at runtime (a database adapter) can grant more", "go_auth")
    {dirs: program_dirs(file, go_sources), pattern: pattern, public: rows, folds: folds, tag: tag}
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
    source.scan(QUALIFIED_CALL).each do |call|
      package_dirs(call[1], body.file_path).each do |pkg|
        @bodies.functions_for(pkg)[call[2]]?.try { |callee| return true if reaches_enforcer?(callee, hops - 1) }
      end
    end
    plain_callees(body).any? { |callee| reaches_enforcer?(callee, hops - 1) }
  end

  # The same-package functions `body` calls (its head line skipped).
  private def plain_callees(body : Noir::GoCalleeExtractor::FunctionBody) : Array(Noir::GoCalleeExtractor::FunctionBody)
    package = @bodies.functions_for(File.dirname(body.file_path))
    code_only(body.source).lines.skip(1).flat_map(&.scan(PLAIN_CALL).map(&.[1])).uniq!.compact_map do |name|
      package[name]?.try { |callee| callee unless callee == body }
    end
  end

  # Same-package functions within `hops` calls of `body`.
  private def reachable_helpers(body : Noir::GoCalleeExtractor::FunctionBody, hops : Int32) : Array(Noir::GoCalleeExtractor::FunctionBody)
    found = [] of Noir::GoCalleeExtractor::FunctionBody
    frontier = [body]
    hops.times do
      frontier = frontier.flat_map { |fn| plain_callees(fn) }.reject { |fn| fn == body || found.includes?(fn) }.uniq!
      found.concat(frontier)
    end
    found
  end

  # The filter writes a response under a negated test (`if !allowed {`),
  # and no earlier absence test (`if token == "" { return }`) lets a caller
  # without a credential through before it.
  private def anonymous_refused?(body : Noir::GoCalleeExtractor::FunctionBody) : Bool
    lines = body.source.lines
    lines.each_with_index do |raw, idx|
      code = code_only(raw).strip
      if (head = code.match(IF_HEAD)) && head[1].split("||").any?(&.strip.matches?(ABSENT_VALUE)) && !code.matches?(NEGATED_IF)
        block = if_block_lines(lines, idx)
        return false if block.any? { |line| code_only(line).strip.matches?(PASS_ON) } && !writes_response?(block, body, 2)
      end
      next unless code.matches?(NEGATED_IF)
      return true if writes_response?(if_block_lines(lines, idx), body, 2)
    end
    false
  end

  # The lines inside the block opened on `idx`.
  private def if_block_lines(lines : Array(String), idx : Int32) : Array(String)
    depth = 0
    block = [] of String
    (idx...lines.size).each do |i|
      code = code_only(lines[i])
      depth += code.count('{') - code.count('}')
      block << lines[i] if i > idx
      break if depth <= 0
    end
    block
  end

  # A response write in `block`, or in a same-package function it calls
  # (`hops` deep).
  private def writes_response?(block : Array(String), owner : Noir::GoCalleeExtractor::FunctionBody, hops : Int32) : Bool
    package = @bodies.functions_for(File.dirname(owner.file_path))
    block.any? do |line|
      code = code_only(line)
      next true if code.matches?(RESPONSE_WRITE) || code.matches?(GoAuthTagger::REJECTS_REQUEST)
      hops > 0 && code.scan(PLAIN_CALL).any? do |call|
        callee = package[call[1]]?
        !callee.nil? && callee != owner && writes_response?(callee.source.lines.skip(1), callee, hops - 1)
      end
    end
  end

  # The subjects a caller without a session is checked as: `*`, and the
  # literals the filter or its helpers return or assign under an absence
  # test (`if user == "" { return "anonymous" }`, `{ user = "guest" }`).
  private def anonymous_subjects(body : Noir::GoCalleeExtractor::FunctionBody, helpers : Array(Noir::GoCalleeExtractor::FunctionBody)) : Set(String)
    subjects = Set{"*"}
    ([body] + helpers).each do |fn|
      lines = fn.source.lines
      lines.each_with_index do |raw, idx|
        head = code_only(raw).strip.match(IF_HEAD) || next
        next unless head[1].split("||").any?(&.strip.matches?(ABSENT_VALUE))
        if_block_lines(lines, idx).each do |line|
          next unless line.matches?(FOLD_TARGET)
          line.scan(STRING_VALUE) { |m| subjects << m[1] unless m[1].empty? }
        end
      end
    end
    subjects << "anonymous" if subjects.size == 1
    subjects
  end

  # `if strings.HasPrefix(p, "/scim") { return "/scim" }`: the prefixes the
  # filter folds a path onto before it asks, longest first.
  private def path_folds(bodies : Array(Noir::GoCalleeExtractor::FunctionBody)) : Array({String, String})
    folds = [] of {String, String}
    bodies.each do |fn|
      lines = fn.source.lines
      lines.each_with_index do |raw, idx|
        prefix = raw.match(HAS_PREFIX) || next
        next unless raw.strip.starts_with?("if ")
        target = if_block_lines(lines, idx).first(2).join.match(FOLD_TARGET) || next
        folds << {prefix[1], target[1]}
      end
    end
    folds.uniq.sort_by! { |(prefix, _)| -prefix.size }
  end

  # The package directories of every program that runs a filter registered
  # in `file`: a `main` package that is (or imports, transitively, within
  # the scan) the registering package. With no `main` package in the scan,
  # the registering file's Go module.
  private def program_dirs(file : String, go_sources : Array(String)) : Set(String)
    by_dir = go_sources.group_by { |source| File.dirname(source) }
    dir_of_import = Hash(String, String).new
    by_dir.each_key { |dir| dir_import_path(dir).try { |import| dir_of_import[import] = dir } }
    closure = ->(root : String) do
      seen = Set{root}
      queue = [root]
      while dir = queue.shift?
        (by_dir[dir]? || [] of String).each do |source|
          quoted_imports(source).each do |import|
            target = dir_of_import[import]?
            next if target.nil? || seen.includes?(target)
            seen << target
            queue << target
          end
        end
      end
      seen
    end
    registering = File.dirname(file)
    dirs = Set(String).new
    by_dir.each do |dir, sources|
      next unless sources.any? { |source| read_file(source).try(&.matches?(PACKAGE_MAIN)) }
      reach = closure.call(dir)
      dirs.concat(reach) if reach.includes?(registering)
    end
    return dirs unless dirs.empty?
    mod = go_module(file)
    by_dir.keys.select { |dir| go_module(File.join(dir, "_.go")) == mod }.to_set
  end

  # The import paths of a Go file, read off its import block with no parse:
  # `program_dirs` walks every file of the program.
  IMPORT_BLOCK = /^import\s*\(([^)]*)\)/m
  IMPORT_LINE  = /^import\s+(?:[\w.]+\s+)?"([^"]+)"/m
  IMPORT_SPEC  = /"([^"]+)"/

  private def quoted_imports(source : String) : Array(String)
    content = read_file(source) || return [] of String
    head = content[0, content.index(/^(?:func|type|var|const)\s/m) || content.size]
    imports = head.scan(IMPORT_LINE).map(&.[1])
    head.scan(IMPORT_BLOCK) { |block| block[1].scan(IMPORT_SPEC) { |spec| imports << spec[1] } }
    imports
  end

  # The public rows of the first policy found in module `mod`, and where;
  # its fields are named by the first model definition that fits them.
  private def casbin_policy(mod : String, go_sources : Array(String), anonymous : Set(String)) : {Array({String, Regex}), String}?
    definitions = [] of {Array(String), String?}
    policies = [] of {Array(Array(String)), Array(Array(String)), String}
    in_module = ->(file : String) { (owner = go_module(file)) == mod || owner.starts_with?(mod + "/") || same_program?(owner, mod) }
    texts_of = ->(file : String) do
      content = read_file(file) || ""
      file.ends_with?(".go") ? content.scan(RAW_STRING).map(&.[1]) : [content]
    end
    sources = go_sources.select { |file| in_module.call(file) }
    # A policy file only when no Go raw string holds one: `.csv` may be data.
    unless sources.any? { |file| texts_of.call(file).any?(&.matches?(/^\s*p\s*,/m)) }
      sources = (collect_files_by_extension(".conf") + collect_files_by_extension(".csv")).select { |file| in_module.call(file) && (File.size(file) rescue 0) <= 1_000_000 } +
                sources
    end
    sources.each do |file|
      texts_of.call(file).each do |text|
        text.match(POLICY_DEFINITION).try { |definition| definitions << {definition[1].split(',').map(&.strip), text.match(POLICY_EFFECT).try(&.[1])} }
        rows = text.lines.compact_map { |line| line.match(CASBIN_POLICY).try(&.[1].split(',').map(&.strip)) }
        roles = text.lines.compact_map { |line| line.match(CASBIN_ROLE).try(&.[1].split(',').map(&.strip)) }
        policies << {rows, roles, file} unless rows.empty?
      end
    end
    # The enforcer's own package first.
    rows, roles, file = policies.find { |(_, _, path)| @enforcer_dirs.includes?(File.dirname(path)) } || policies.first? || return
    where = base_relative_path(file).lchop('/')
    # The model whose `p` has as many fields as the policy's lines and
    # names a field the lines fill with paths.
    width = rows.first.size
    definitions << {["sub", "obj", "act"], nil.as(String?)} if width == 3
    layout = definitions.each do |(names, effect)|
      next unless names.size == width
      path_col = names.index(&.matches?(/path|url/i)) || names.index { |n| n.downcase == "obj" } || next
      method_col = names.index(&.matches?(/method|\Aact/i)) || next
      break {names, effect, path_col, method_col} if rows.count { |row| row[path_col]?.try(&.starts_with?('/')) } * 2 > rows.size
    end
    names, effect, path_col, method_col = layout || return
    # Only the allow-override effect is read: under a deny-override or
    # priority model a grant can be taken back by a row this does not weigh.
    return if effect && effect.gsub(/\s+/, "") != ALLOW_OVERRIDE
    eft_col = names.index { |n| n.downcase == "eft" }
    # `g, anonymous, public_role`: the roles a session-less caller has.
    loop do
      added = roles.select { |role| role.size >= 2 && anonymous.includes?(role[0]) && !anonymous.includes?(role[1]) }
      break if added.empty?
      added.each { |role| anonymous << role[1] }
    end
    subjects = names.each_index.select { |i| names[i].downcase.starts_with?("sub") }.to_a
    public = rows.compact_map do |row|
      next unless row.size == names.size
      next if eft_col && row[eft_col] == "deny"
      next unless subjects.all? { |i| anonymous.includes?(row[i]) }
      next unless row.each_index.all? { |i| subjects.includes?(i) || i == path_col || i == method_col || i == eft_col || row[i] == "*" }
      {row[method_col], key_match(row[path_col])}
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
