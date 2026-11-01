# Part of `GoAuthTagger`: a gRPC / Connect interceptor that lets a request
# through by the procedure it calls.
#
#   var PublicMethods = map[string]struct{}{"/app.v1.AuthService/SignIn": {}}
#   func IsPublicMethod(p string) bool { _, ok := PublicMethods[p]; return ok }
#   func (a *Authorizer) CheckAccess(ctx context.Context, p string, r *Result) error {
#       if r != nil { return nil }
#       if !IsPublicMethod(p) { return ErrUnauthenticated }
#       ...
#   }
#   func (in *AuthInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
#       ... in.authorizer.CheckAccess(ctx, req.Spec().Procedure, result) ...
#   connect.WithInterceptors(NewAuthInterceptor(authorizer))
#
# A package-level list of procedure names (`/pkg.Service/Method`) is read
# through its membership tests: an index (`List[p]`, truthy: a zero value
# such as `""` is not a member), a `v, ok := List[p]` presence test, or a
# `func X(p string) bool` whose return is one of those (`return ok`,
# `return !ok`, `return List[p]`, `slices.Contains(List, p)`); a helper
# whose return reads otherwise is not followed. A test gates when
#
# * negated (`!IsPublic(p)`, `!(Public[p] || authed)`, `!ok`) and its block
#   returns a refusal — an error built with an auth code (`status.Error(
#   codes.Unauthenticated, ...)`, `connect.NewError(connect.CodePermission
#   Denied, ...)`) or an `ErrUnauthenticated`-style sentinel, never a
#   comparison or a counter: every procedure the list does not name is
#   refused (an allow-list);
# * positive and its block refuses or returns a check's error (`if
#   AdminOnly[m] { if err := requireAdmin(ctx); err != nil { return nil,
#   err } }`): the listed procedures are refused (a deny-list);
# * positive, its block hands the request on (`return handler(ctx, req)`,
#   `next(...)`, a check's `return nil`), no refusal comes before it, and
#   one comes after: an allow-list.
#
# Procedures an earlier pass in the same function lets through
# (`strings.HasPrefix(m, "/pkg.Auth/")`, `case "/pkg.S/M":`, `m == "..."`)
# stay open. Another condition joined with `&&` that reads a setting
# (`cfg.RequireAuth && !Public[m]`) is named in the guard: it can open the
# procedure. A listed procedure an allow-list's function can still refuse
# later (memos' private access mode) gets an `anonymous` note saying so.
#
# The function holding the test has to be an interceptor (`WrapUnary`, a
# `grpc.UnaryServerInfo` parameter, a grpc-gateway middleware) or be called
# from one, and that interceptor has to be installed (`grpc.UnaryInterceptor
# (X)`, `ChainUnaryInterceptor`, `connect.WithInterceptors(...)`,
# `runtime.WithMiddlewares(...)`). A unary interceptor does not cover a
# streaming `rpc` (one with `stream` in the `.proto`); a stream one does. A
# service registered on a server built without options (`grpc.NewServer()`,
# `NewXServiceHandler(impl)`) is reachable unguarded, so it is not gated.
# A gate covers the proto packages its list names. Connect endpoints carry
# the procedure as their URL; a gRPC-gateway route from a `.proto` file is
# mapped back through its `package`, `service` and `rpc` lines.
module GoRpcProcedureGate
  RPC_TECHS = %w[go_connect_rpc grpc]

  RPC_PROCEDURE  = /\A\/((?:[A-Za-z_]\w*\.)*)([A-Za-z_]\w*)\/[A-Za-z_]\w*\z/
  PROCEDURE_KEY  = /"(\/(?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*\/[A-Za-z_]\w*)"/
  PROCEDURE_LIST = /\A(?:var\s+)?([A-Za-z_]\w*)\s*=\s*(?:map\s*\[\s*string\s*\].*|\[\]\s*string\s*)\{\s*\z/
  LIST_ENTRY     = /\A"([^"]*)"\s*(?::\s*(.*?))?\s*,?\s*(?:\/\/.*)?\z/
  ZERO_VALUE     = Set{"\"\"", "0", "false", "nil"}
  BOOL_FUNC      = /\Afunc\s+(?:\([^)]*\)\s*)?(\w+)\s*\([^)]*\)\s*bool\s*\{/
  FUNC_HEAD      = /\Afunc\s+(?:\([^)]*\)\s*)?(\w+)\s*\(/
  # A refusal: a returned error built with an auth code, or a sentinel.
  RPC_REFUSAL = /\breturn\b.*?(?:\bstatus\s*\.\s*(?:Error|Errorf|New|Newf)\s*\(\s*codes\s*\.\s*(Unauthenticated|PermissionDenied)\b|\bconnect\s*\.\s*NewError\s*\(\s*connect\s*\.\s*Code(Unauthenticated|PermissionDenied)\b|\bErr(Unauthenticated|Unauthorized|PermissionDenied|Forbidden)\w*\b)/
  # A check's own error handed back: `return nil, err`.
  ERROR_RETURN = /\Areturn\s+(?:nil\s*,\s*)?\w*[Ee]rr\w*\s*\z/
  # Handing the request on: `return handler(ctx, req)`, `return next(ctx, req)`.
  HAND_ON    = /\Areturn\s+(?:handler|next|h|invoker)\s*\(/
  RETURN_NIL = /\Areturn\s+nil\s*\z/
  # A function that is itself an interceptor, and of which kind.
  UNARY_MARK  = /\bWrapUnary\b|\bUnaryServerInfo\b|\bruntime\s*\.\s*HandlerFunc\b/
  STREAM_MARK = /\bWrapStreamingHandler\b|\bStreamServerInfo\b/
  # Installing interceptors on a server or handler.
  INSTALL = /\b(?:grpc\s*\.\s*(?:Chain)?(?:Unary|Stream)Interceptor|connect\s*\.\s*WithInterceptors|runtime\s*\.\s*WithMiddlewares)\s*\(/
  # `pb.RegisterNoteServiceServer(s, impl)` / `apiconnect.NewNoteServiceHandler(impl)`.
  GRPC_REGISTER    = /\bRegister(\w+Service)Server\s*\(\s*(\w+)\s*,/
  CONNECT_BARE     = /\bNew(\w+Service)Handler\s*\(\s*[^,()]+\s*\)/
  PROTO_PACKAGE    = /^\s*package\s+([\w.]+)\s*;/
  PROTO_SERVICE    = /^\s*service\s+(\w+)\s*\{/
  PROTO_RPC        = /^\s*rpc\s+(\w+)\s*\(/
  PROTO_STREAM_RPC = /^\s*rpc\s+(\w+)\s*\(\s*stream\b|^\s*rpc\s+(\w+)\s*\([^)]*\)\s*returns\s*\(\s*stream\b/
  # `cfg.RequireAuth`, `!s.opts.Public`: a setting, not a request value.
  SETTING_PART = /\A!?\s*[a-z]\w*(?:\.[A-Za-z]\w*)+\z/
  # Earlier passes: `strings.HasPrefix(m, "/pkg.S/")`, `m == "/pkg.S/M"`, `case "...":`.
  PREFIX_PASS = /strings\s*\.\s*HasPrefix\s*\(\s*[\w.()]+\s*,\s*"([^"]+)"\s*\)/
  EQUAL_PASS  = /(?:==)\s*"(\/[^"]+)"/
  CASE_PASS   = /\Acase\s+(.+):\z/
  MAX_HELPERS = 64
  # `_, ok := List[p]`: the presence variable and the list.
  OK_LOOKUP = /\b\w+\s*,\s*(\w+)\s*:?=\s*(\w+)\s*\[/
  # `role != ""`: a variable compared with a value.
  COMPARISON = /\A(\w+)\s*(!=|==)\s*(\S+)\z/
  # `func (in *AuthInterceptor) WrapUnary(`: the receiver's type.
  METHOD_RECEIVER_TYPE = /\Afunc\s*\(\s*\w*\s*\*?\s*(\w+)\s*\)/

  # One gate: its list's procedures and proto packages, whether it lets
  # them in (`allow`) or refuses them, whether it covers streaming RPCs,
  # what an earlier pass lets through, the guard, and the note for listed
  # procedures a later check can still refuse (with the lists exempt from
  # it).
  record ProcedureGate,
    procedures : Set(String),
    packages : Set(String),
    allow : Bool,
    streams : Bool,
    exempt_prefixes : Array(String),
    exempt : Set(String),
    tag : Tag,
    later : {String, Int32, Int32}? = nil,
    note : Tag? = nil

  # A list: its name, entries (procedure => value text), file.
  alias ProcedureList = {name: String, entries: Hash(String, String), file: String}

  @procedure_gates : Array(ProcedureGate)? = nil
  @proto_procedures = Hash({String, Int32}, String?).new
  # `{file, row}` of each positive "hand on" test, per list name.
  @procedure_passes = Hash(String, Array({String, Int32})).new

  private def rpc_procedure_guard(endpoint : Endpoint) : Tag?
    procedure = endpoint_procedure(endpoint) || return
    match = procedure.match(RPC_PROCEDURE) || return
    package = match[1].rchop('.')
    streaming = streaming_procedures.includes?(procedure)
    procedure_gates.each do |gate|
      next unless gate.packages.includes?(package)
      next if bare_services.includes?(match[2])
      next if streaming && !gate.streams
      listed = gate.procedures.includes?(procedure)
      if gate.allow
        next if gate.exempt.includes?(procedure) || gate.exempt_prefixes.any? { |prefix| procedure.starts_with?(prefix) }
        return gate.tag unless listed
        if (note = gate.note) && (later = gate.later) && !later_exempt?(procedure, later)
          endpoint.add_tag(note)
        end
      elsif listed
        return gate.tag
      end
    end
    nil
  end

  # Whether a list with a "hand on" test between the gate and the later
  # refusal names `procedure` (memos' bootstrap list).
  private def later_exempt?(procedure : String, later : {String, Int32, Int32}) : Bool
    file, from, to = later
    procedure_list_index.any? do |list|
      next false unless list[:entries].has_key?(procedure)
      (@procedure_passes[list[:name]]? || [] of {String, Int32}).any? { |(pass_file, row)| pass_file == file && from < row < to }
    end
  end

  private def endpoint_procedure(endpoint : Endpoint) : String?
    return endpoint.url if endpoint.details.technology == "go_connect_rpc" && endpoint.url.matches?(RPC_PROCEDURE)
    endpoint.details.code_paths.each do |info|
      next unless info.path.ends_with?(".proto") && (line = info.line)
      found = @proto_procedures.put_if_absent({info.path, line}) { proto_procedure(info.path, line) }
      return found if found
    end
    nil
  end

  # `/package.Service/Rpc` for the `rpc` declared at or above `line`.
  private def proto_procedure(path : String, line : Int32) : String?
    lines = read_file_lines(path) || return
    idx = Math.min(line, lines.size) - 1
    rpc = nil
    while idx >= 0
      text = lines[idx]
      if rpc.nil? && (m = text.match(PROTO_RPC))
        rpc = m[1]
      elsif m = text.match(PROTO_SERVICE)
        break unless rpc
        package = nil
        lines.each { |l| (pm = l.match(PROTO_PACKAGE)) && (package = pm[1]) && break }
        return package ? "/#{package}.#{m[1]}/#{rpc}" : "/#{m[1]}/#{rpc}"
      end
      idx -= 1
    end
    nil
  end

  @streaming_procedures : Set(String)? = nil

  # The procedures every `.proto` in the scan declares with `stream`.
  private def streaming_procedures : Set(String)
    @streaming_procedures ||= begin
      found = Set(String).new
      collect_files_by_extension(".proto").each do |path|
        lines = read_file_lines(path) || next
        package = nil
        service = nil
        lines.each do |line|
          if m = line.match(PROTO_PACKAGE)
            package = m[1]
          elsif m = line.match(PROTO_SERVICE)
            service = m[1]
          elsif (m = line.match(PROTO_STREAM_RPC)) && service
            name = m[1]? || m[2]?
            found << (package ? "/#{package}.#{service}/#{name}" : "/#{service}/#{name}")
          end
        end
      end
      found
    end
  end

  @bare_services : Set(String)? = nil

  # Services registered where no interceptor can reach them: on a
  # `grpc.NewServer()` built in the same function with no options, or a
  # Connect handler built with the implementation alone.
  private def bare_services : Set(String)
    @bare_services ||= begin
      found = Set(String).new
      rpc_go_sources.each do |file|
        content = read_file(file) || next
        next unless content.includes?("Register") || content.includes?("Handler(")
        rpc_each_function(file) do |_head, body|
          code = code_only(body)
          code.scan(GRPC_REGISTER) do |m|
            found << m[1] if code.matches?(/\b#{Regex.escape(m[2])}\s*:?=\s*grpc\s*\.\s*NewServer\s*\(\s*\)/)
          end
          code.scan(CONNECT_BARE) { |m| found << m[1] }
        end
      end
      found
    end
  end

  @rpc_go_sources : Array(String)? = nil

  private def rpc_go_sources : Array(String)
    @rpc_go_sources ||= collect_files_by_extension(".go").reject(&.ends_with?("_test.go"))
  end

  @procedure_list_index : Array(ProcedureList)? = nil

  private def procedure_list_index : Array(ProcedureList)
    @procedure_list_index ||= begin
      lists = [] of ProcedureList
      rpc_go_sources.each do |file|
        content = read_file(file) || next
        next unless content.matches?(PROCEDURE_KEY)
        procedure_lists(content).each { |name, entries| lists << {name: name, entries: entries, file: file} }
      end
      lists
    end
  end

  private def procedure_gates : Array(ProcedureGate)
    @procedure_gates ||= begin
      gates = [] of ProcedureGate
      procedure_list_index.each do |list|
        # One list that does not read (a regex that will not build) must
        # not take the rest of `go_auth` down with it.
        gates.concat(gates_for_list(list))
      rescue ex
        @logger.debug "go_auth: procedure list #{list[:name]} skipped: #{ex.message}"
      end
      gates
    end
  end

  # Package-level `var Name = map[string]T{...}` / `[]string{...}` blocks
  # whose keys are all procedure names, with each entry's value text.
  private def procedure_lists(content : String) : Array({String, Hash(String, String)})
    lists = [] of {String, Hash(String, String)}
    name = nil
    entries = Hash(String, String).new
    clean = true
    content.each_line do |line|
      if name
        if line.starts_with?('}')
          lists << {name, entries} if clean && !entries.empty?
          name = nil
          next
        end
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?("//")
        entry = stripped.match(LIST_ENTRY)
        if entry && entry[1].matches?(RPC_PROCEDURE)
          entries[entry[1]] = (entry[2]? || "").strip
        else
          clean = false
        end
      elsif m = line.rstrip.match(PROCEDURE_LIST)
        name = m[1]
        entries = Hash(String, String).new
        clean = true
      end
    end
    lists
  end

  # The tests of `name`: its own index and the bool helpers (anywhere in the
  # scan) whose return is a readable membership test.
  private def membership_tests(name : String) : Array({String, Bool, Bool})
    tests = [] of {String, Bool, Bool}
    tests << {Regex.escape(name) + "\\s*[\\[]", false, false}
    seen = Set(String).new
    escaped = Regex.escape(name)
    rpc_go_sources.each do |file|
      content = read_file(file) || next
      next unless content.includes?(name)
      rpc_each_function(file) do |head, body|
        bool_fn = head.match(BOOL_FUNC) || next
        next unless body.includes?(name) && seen.size < MAX_HELPERS && seen.add?(bool_fn[1])
        reading = helper_reading(body, escaped) || next
        tests << {Regex.escape(bool_fn[1]) + "\\s*\\(", reading[0], reading[1]}
      end
    end
    tests
  end

  # `{presence, inverse}` of a bool helper's single return: `ok` / `!ok`
  # after `_, ok := L[p]`, `L[p]` / `!L[p]`, `slices.Contains(L, p)`.
  private def helper_reading(body : String, name : String) : {Bool, Bool}?
    returns = code_only(body).lines.map(&.strip).select(&.starts_with?("return "))
    return unless returns.size == 1
    expr = returns.first.lchop("return ").strip
    inverse = expr.starts_with?('!')
    expr = expr.lchop('!').strip
    ok_var = body.scan(OK_LOOKUP).find { |m| m[2] == name }.try(&.[1])
    if ok_var && expr == ok_var
      {true, inverse}
    elsif expr.matches?(/\A#{name}\s*\[[^\]]+\]\z/)
      {false, inverse}
    elsif expr.matches?(/\Aslices\s*\.\s*Contains\s*\(\s*#{name}\s*,/)
      {true, inverse}
    end
  end

  # Whether the condition of `written` (an `if` line) tests membership
  # negated, `true` / `false`, or `nil` when it does not read cleanly; with
  # the setting it is joined to, if any.
  private def test_polarity(written : String, tests : Array({String, Bool, Bool}), regexes : Array(Regex)) : {Bool, Bool, String?}?
    m = written.match(/\A(?:\}\s*else\s+)?if\s+(?:(.*?);\s*)?(.+?)\s*\{\z/) || return
    init = m[1]?
    cond = m[2]
    # `if _, ok := L[p]; !ok {` / `if role := L[p]; role != "" && ...`.
    if init && (which = regexes.index { |re| init.matches?(re) })
      presence = !init.matches?(/\A\s*\w+\s*:?=/) || tests[which][1]
      var = init.match(/\A\s*(?:\w+\s*,\s*)?(\w+)\s*:?=/).try(&.[1]) || return
      parts = Noir::TopLevelSplit.split(cond, "&&", Noir::TopLevelSplit::Rules.new).map(&.strip)
      part = parts.find(&.matches?(/\b#{Regex.escape(var)}\b/)) || return
      compared = part.match(COMPARISON)
      zero = compared && compared[1] == var && ZERO_VALUE.includes?(compared[3]) ? compared[2] : nil
      negated = if part == var || zero == "!="
                  false
                elsif part == "!#{var}" || zero == "=="
                  true
                else
                  return
                end
      setting = parts.find { |other| other != part && other.matches?(SETTING_PART) }
      return {negated ^ tests[which][2], presence, setting}
    end
    # `!(Public[p] || authed)`: the test negated with what it is or-ed with.
    if cond.starts_with?("!(") && cond.ends_with?(')')
      inner = cond[2...-1]
      ors = Noir::TopLevelSplit.split(inner, "||", Noir::TopLevelSplit::Rules.new).map(&.strip)
      return if ors.size < 2 && inner.includes?("&&")
      which = nil
      ors.each { |part| (i = regexes.index { |re| part.matches?(/\A(?:\w+\s*\.\s*)?#{re.source}[^&|]*\z/) }) && (which = i) }
      return unless which
      return {!tests[which][2], tests[which][1], nil}
    end
    parts = Noir::TopLevelSplit.split(cond, "&&", Noir::TopLevelSplit::Rules.new).map(&.strip)
    parts.each do |part|
      or_parts = Noir::TopLevelSplit.split(part, "||", Noir::TopLevelSplit::Rules.new).map(&.strip)
      or_parts.each do |piece|
        which = regexes.index { |re| piece.matches?(re) } || next
        bare = piece.lchop('!').strip
        # The test must be the whole piece: `IsPublic(p)` / `!L[p]`.
        return if bare.matches?(/[=<>]/)
        return unless bare.matches?(/\A(?:\w+\s*\.\s*)?#{regexes[which].source}[^()]*(?:\([^()]*\))?[^&|]*\z/)
        negated = piece.starts_with?('!') ^ tests[which][2]
        setting = parts.find { |other| other != part && other.matches?(SETTING_PART) }
        return {negated, tests[which][1], setting}
      end
    end
    nil
  end

  # `source` as a regex starting at a word, or nil when it will not build.
  private def word_regex(source : String) : Regex?
    Regex.new("(?<![\\w])" + source)
  rescue ArgumentError
    nil
  end

  private def gates_for_list(list : ProcedureList) : Array(ProcedureGate)
    name = list[:name]
    tests = membership_tests(name)
    regexes = tests.compact_map { |(source, _, _)| word_regex(source) }
    return [] of ProcedureGate unless regexes.size == tests.size
    any_test = Regex.union(regexes)
    gates = [] of ProcedureGate
    rpc_go_sources.each do |file|
      content = read_file(file) || next
      next unless tests.any? { |(source, _, _)| content.matches?(Regex.new(source)) rescue false }
      lines = read_file_lines(file) || next
      fn_name = nil
      fn_start = 0
      fn_error = false
      lines.each_with_index do |raw, idx|
        if head = raw.match(FUNC_HEAD)
          fn_name = head[1]
          fn_start = idx
          fn_error = raw.rstrip.ends_with?("error {")
        end
        line = code_only(raw).strip
        next unless line.starts_with?("if ") || line.starts_with?("} else if ")
        written = raw.strip
        next unless written.matches?(any_test)
        polarity = test_polarity(written, tests, regexes) || next
        negated, presence, setting = polarity
        block, block_end = rpc_if_block(lines, idx)
        block_lines = block.lines.map { |l| code_only(l).strip }
        refuses = block_lines.any?(&.matches?(RPC_REFUSAL))
        hands_on = block_lines.any? { |l| l.matches?(HAND_ON) || (fn_error && l.matches?(RETURN_NIL)) }
        allow = negated
        if !negated && !refuses && hands_on
          (@procedure_passes[name] ||= [] of {String, Int32}) << {file, idx}
          next if lines[fn_start...idx].any? { |l| code_only(l).matches?(RPC_REFUSAL) }
          rest = rpc_function_text(lines, fn_start).lines[(block_end - fn_start + 1)..]? || [] of String
          next unless rest.any? { |l| code_only(l).strip.matches?(RPC_REFUSAL) }
          allow = true
        elsif negated
          next unless refuses
        else
          next unless refuses || block_lines.any?(&.matches?(ERROR_RETURN))
        end
        holder = fn_name || next
        kinds = interceptor_kinds(holder, lines, fn_start)
        next if kinds.empty?
        procedures = presence ? list[:entries].keys.to_set : list[:entries].reject { |_, value| ZERO_VALUE.includes?(value) }.keys.to_set
        packages = list[:entries].keys.compact_map { |p| p.match(RPC_PROCEDURE).try(&.[1].rchop('.')) }.to_set
        authz = block_lines.any?(&.matches?(/PermissionDenied|Forbidden/))
        checker = base_relative_path(file).lchop('/')
        where = base_relative_path(list[:file]).lchop('/')
        description = if allow
                        "Protected by RPC interceptor check #{holder} (#{checker}): only procedures listed in #{name} (#{where}) are let through without credentials"
                      else
                        "Protected by RPC interceptor check #{holder} (#{checker}): procedures listed in #{name} (#{where}) are refused"
                      end
        description += "; a setting can make it public: `#{setting}`" if setting
        tag = Tag.new(authz ? "authz" : "auth", description, "go_auth", file, idx + 1)
        exempt_prefixes, exempt = earlier_passes(lines, fn_start, idx)
        later = nil
        note = nil
        if allow && fn_error
          fn_end = fn_start + rpc_function_text(lines, fn_start).lines.size - 1
          if later_row = ((block_end + 1)..fn_end).find { |row| lines[row]?.try { |l| code_only(l).strip.matches?(RPC_REFUSAL) } }
            later = {file, block_end, later_row}
            note = Tag.new("anonymous", "Listed in #{name} (#{where}), so #{holder} lets anonymous callers through, but a later check in #{holder} (#{checker}:#{later_row + 1}) can still refuse them: a setting can require credentials", "go_auth", file, later_row + 1)
          end
        end
        gates << ProcedureGate.new(procedures, packages, allow, kinds.includes?(:stream), exempt_prefixes, exempt, tag, later, note)
        break
      end
      break unless gates.empty?
    end
    gates
  end

  # What a pass before row `upto` of the function at `start` lets through:
  # `strings.HasPrefix(m, "/pkg.S/")` prefixes, `m == "..."` / `case "...":` procedures.
  private def earlier_passes(lines : Array(String), start : Int32, upto : Int32) : {Array(String), Set(String)}
    prefixes = [] of String
    exact = Set(String).new
    (start...upto).each do |row|
      raw = lines[row].strip
      passes = -> { lines[(row + 1)..Math.min(row + 3, upto)].any? { |l| code_only(l).strip.matches?(HAND_ON) } }
      if raw.starts_with?("if ") && (prefix = raw.match(PREFIX_PASS)) && passes.call
        prefixes << prefix[1]
      elsif raw.starts_with?("if ") && raw.matches?(EQUAL_PASS) && passes.call
        raw.scan(EQUAL_PASS) { |m| exact << m[1] }
      elsif (kase = raw.match(CASE_PASS)) && passes.call
        kase[1].scan(/"(\/[^"]+)"/) { |m| exact << m[1] }
      end
    end
    {prefixes, exact}
  end

  # The block opened on `idx` and the row of its closing brace.
  private def rpc_if_block(lines : Array(String), idx : Int32) : {String, Int32}
    depth = 0
    text = String::Builder.new
    last = idx
    (idx...Math.min(lines.size, idx + 40)).each do |i|
      line = code_only(lines[i])
      text << lines[i] << '\n' if i > idx
      depth += line.count('{') - line.count('}')
      last = i
      break if depth <= 0
    end
    {text.to_s, last}
  end

  # The kinds (`:unary`, `:stream`) of installed interceptors that are, or
  # call, `holder`.
  private def interceptor_kinds(holder : String, lines : Array(String), start : Int32) : Set(Symbol)
    kinds = Set(Symbol).new
    own = rpc_function_text(lines, start)
    candidates = [] of {String, String}
    candidates << {lines[start], own} if own.matches?(UNARY_MARK) || own.matches?(STREAM_MARK)
    call = /(?<![\w])(?:\w+\s*\.\s*)*#{Regex.escape(holder)}\s*\(/
    rpc_go_sources.each do |file|
      content = read_file(file) || next
      next unless content.includes?(holder)
      rpc_each_function(file) do |head, body|
        next if head.includes?(" #{holder}(")
        text = head + body
        candidates << {head, text} if body.matches?(call) && (text.matches?(UNARY_MARK) || text.matches?(STREAM_MARK))
      end
    end
    candidates.each do |(head, text)|
      # A grpc-gateway middleware closure is installed by the function
      # that builds it.
      next unless text.matches?(/\bWithMiddlewares\s*\(/) || installed?(head)
      kinds << :unary if text.matches?(UNARY_MARK)
      kinds << :stream if text.matches?(STREAM_MARK)
    end
    kinds
  end

  @installs : String? = nil

  # The argument text of every interceptor install in the scan.
  private def install_text : String
    @installs ||= begin
      text = String::Builder.new
      rpc_go_sources.each do |file|
        content = read_file(file) || next
        next unless content.matches?(INSTALL)
        lines = code_only(content).lines
        lines.each_with_index do |line, idx|
          next unless line.matches?(INSTALL)
          depth = 0
          (idx...Math.min(lines.size, idx + 12)).each do |i|
            text << lines[i] << '\n'
            depth += lines[i].count('(') - lines[i].count(')')
            break if depth <= 0
          end
        end
      end
      text.to_s
    end
  end

  # An interceptor is installed when an install names it: the function
  # (`grpc.UnaryInterceptor(AuthUnary)`), its receiver type (`&Mw{}`), a
  # constructor returning that type (`NewAuthInterceptor(a)`).
  private def installed?(head : String) : Bool
    installs = install_text
    return false if installs.empty?
    if receiver = head.match(METHOD_RECEIVER_TYPE)
      type = receiver[1]
      return true if installs.matches?(/\b#{Regex.escape(type)}\b/)
      constructors = Set(String).new
      rpc_go_sources.each do |file|
        content = read_file(file) || next
        content.scan(/^func\s+(\w+)\s*\([^)]*\)\s*\*?#{Regex.escape(type)}\b/m) { |m| constructors << m[1] }
      end
      return constructors.any? { |ctor| installs.matches?(/\b#{Regex.escape(ctor)}\s*\(/) }
    end
    name = head.match(FUNC_HEAD).try(&.[1]) || return false
    installs.matches?(/\b#{Regex.escape(name)}\b/)
  end

  private def rpc_function_text(lines : Array(String), start : Int32) : String
    text = String::Builder.new
    (start...lines.size).each do |i|
      text << lines[i] << '\n'
      break if i > start && lines[i].starts_with?('}')
    end
    text.to_s
  end

  # Each top-level `func` of `file`: its head line and its body.
  private def rpc_each_function(file : String, &)
    lines = read_file_lines(file) || return
    head = nil
    body = String::Builder.new
    lines.each do |line|
      if line.starts_with?("func ")
        head = line
        body = String::Builder.new
        if line.rstrip.ends_with?('}')
          yield head, ""
          head = nil
        end
      elsif head
        if line.starts_with?('}')
          yield head, body.to_s
          head = nil
        else
          body << line << '\n'
        end
      end
    end
  end
end
