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
#   // and an interceptor that calls it:
#   func (in *AuthInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
#       ... in.authorizer.CheckAccess(ctx, req.Spec().Procedure, result) ...
#
# A package-level list of procedure names (`/pkg.Service/Method`) whose
# negated membership test (`!IsPublicMethod(p)`, `!PublicMethods[p]`,
# `_, ok := PublicMethods[p]; !ok`) guards a refusal (an `Unauthenticated` /
# `PermissionDenied` code or an `ErrUnauthenticated`-style sentinel) is an
# allow-list: every other procedure of that proto package is refused. A
# plain (positive) membership test guarding a refusal is a deny-list: the
# listed procedures are refused. The function holding the test has to be
# an interceptor (`WrapUnary`, a `grpc.UnaryServerInfo` parameter) or be
# called from one. Connect endpoints carry the procedure as their URL; a
# gRPC-gateway route from a `.proto` file is mapped back through its
# `package`, `service` and `rpc` lines.
module GoRpcProcedureGate
  RPC_TECHS = %w[go_connect_rpc grpc]

  RPC_PROCEDURE  = /\A\/((?:[A-Za-z_]\w*\.)*)([A-Za-z_]\w*)\/[A-Za-z_]\w*\z/
  PROCEDURE_KEY  = /"(\/(?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*\/[A-Za-z_]\w*)"/
  PROCEDURE_LIST = /\A(?:var\s+)?([A-Za-z_]\w*)\s*=\s*(?:map\s*\[\s*string\s*\].*|\[\]\s*string\s*)\{\s*\z/
  BOOL_FUNC      = /\Afunc\s+(?:\([^)]*\)\s*)?(\w+)\s*\([^)]*\)\s*bool\s*\{/
  FUNC_HEAD      = /\Afunc\s+(?:\([^)]*\)\s*)?(\w+)\s*\(/
  RPC_REFUSAL    = /\b(?:codes|connect)\s*\.\s*(?:Code)?(Unauthenticated|PermissionDenied)\b|\bErr(Unauthenticated|Unauthorized|PermissionDenied|Forbidden)\w*\b/
  # A function that is itself an interceptor.
  INTERCEPTOR_MARK = /\bWrapUnary\b|\bWrapStreamingHandler\b|\bUnaryServerInfo\b|\bStreamServerInfo\b|\bruntime\s*\.\s*HandlerFunc\b/
  PROTO_PACKAGE    = /^\s*package\s+([\w.]+)\s*;/
  PROTO_SERVICE    = /^\s*service\s+(\w+)\s*\{/
  PROTO_RPC        = /^\s*rpc\s+(\w+)\s*\(/

  # A list found in the scan: the procedures it names and their proto
  # packages, whether it lets them in (`allow`) or refuses them, the tag.
  alias ProcedureGate = {procedures: Set(String), packages: Set(String), allow: Bool, tag: Tag}

  @procedure_gates : Array(ProcedureGate)? = nil
  @proto_procedures = Hash({String, Int32}, String?).new

  private def rpc_procedure_guard(endpoint : Endpoint) : Tag?
    procedure = endpoint_procedure(endpoint) || return
    match = procedure.match(RPC_PROCEDURE) || return
    package = match[1].rchop('.')
    procedure_gates.each do |gate|
      next unless gate[:packages].includes?(package)
      listed = gate[:procedures].includes?(procedure)
      return gate[:tag] if listed != gate[:allow]
    end
    nil
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

  private def procedure_gates : Array(ProcedureGate)
    @procedure_gates ||= begin
      gates = [] of ProcedureGate
      go_sources = collect_files_by_extension(".go").reject(&.ends_with?("_test.go"))
      by_dir = go_sources.group_by { |file| File.dirname(file) }
      go_sources.each do |file|
        content = read_file(file) || next
        next unless content.matches?(PROCEDURE_KEY)
        procedure_lists(content).each do |name, procedures|
          gates.concat(gates_for_list(name, procedures, file, by_dir[File.dirname(file)], go_sources))
        end
      end
      gates
    end
  end

  # Package-level `var Name = map[string]T{...}` / `[]string{...}` blocks
  # whose keys are all procedure names.
  private def procedure_lists(content : String) : Array({String, Set(String)})
    lists = [] of {String, Set(String)}
    name = nil
    procedures = Set(String).new
    clean = true
    content.each_line do |line|
      if name
        if line.starts_with?('}')
          lists << {name, procedures} if clean && !procedures.empty?
          name = nil
          next
        end
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?("//")
        key = stripped.match(/\A"([^"]*)"/)
        if key && key[1].matches?(RPC_PROCEDURE)
          procedures << key[1]
        else
          clean = false
        end
      elsif m = line.rstrip.match(PROCEDURE_LIST)
        name = m[1]
        procedures = Set(String).new
        clean = true
      end
    end
    lists
  end

  private def gates_for_list(name : String, procedures : Set(String), file : String, package_files : Array(String),
                             go_sources : Array(String)) : Array(ProcedureGate)
    # Membership functions: `func IsPublic(p string) bool { ... Name ... }`.
    tests = [Regex.escape(name) + "\\s*\\["]
    package_files.each do |pf|
      rpc_each_function(pf) do |head, body|
        next unless (bool_fn = head.match(BOOL_FUNC)) && body.matches?(/\b#{Regex.escape(name)}\b/)
        tests << Regex.escape(bool_fn[1]) + "\\s*\\("
      end
    end
    test = Regex.new("(!\\s*)?\\b(?:#{tests.join('|')})")

    gates = [] of ProcedureGate
    package_files.each do |pf|
      lines = read_file_lines(pf) || next
      fn_name = nil
      fn_start = 0
      lines.each_with_index do |raw, idx|
        if head = raw.match(FUNC_HEAD)
          fn_name = head[1]
          fn_start = idx
        end
        line = code_only(raw).strip
        next unless line.starts_with?("if ") || line.starts_with?("} else if ")
        written = raw.strip
        next unless hit = written.match(test)
        allow = !hit[1]?.nil?
        # `if _, ok := Name[p]; !ok {`
        allow = true if !allow && (cond = written.split(';', 2)[1]?) && cond.strip.starts_with?("!") && written.split(';', 2)[0].matches?(test)
        block, block_end = rpc_if_block(lines, idx)
        refusal = block.match(RPC_REFUSAL)
        # `if Public[info.FullMethod] { return handler(ctx, req) }` with the
        # refusal after it: the listed procedures skip the check. Not when a
        # refusal comes first: that test only narrows a gate already passed
        # (`if IsBootstrap(p) { return nil }` after `!IsPublic(p)`), and
        # what it leaves for later is a setting's call.
        if refusal.nil? && !allow && block.includes?("return") &&
           !lines[fn_start...idx].any?(&.matches?(RPC_REFUSAL))
          rest = function_text(lines, fn_start).lines[(block_end - fn_start + 1)..]?.try(&.join('\n')) || ""
          refusal = rest.match(RPC_REFUSAL)
          allow = true if refusal
        end
        next unless refusal
        next unless (holder = fn_name) && interceptor_reaches?(holder, lines, fn_start, go_sources)
        authz = (refusal[1]? || refusal[2]? || "").matches?(/Permission|Forbidden/)
        where = base_relative_path(file).lchop('/')
        checker = base_relative_path(pf).lchop('/')
        description = allow ? "Protected by RPC interceptor check #{holder} (#{checker}): only procedures listed in #{name} (#{where}) are let through without credentials" : "Protected by RPC interceptor check #{holder} (#{checker}): procedures listed in #{name} (#{where}) are refused"
        packages = procedures.compact_map { |p| p.match(RPC_PROCEDURE).try(&.[1].rchop('.')) }.to_set
        gates << {procedures: procedures, packages: packages, allow: allow, tag: Tag.new(authz ? "authz" : "auth", description, "go_auth")}
        break
      end
      break unless gates.empty?
    end
    gates
  end

  # The body of the `if` opened on `idx` and the row of its closing brace.
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

  # `holder` is an interceptor, or a call to it sits in one.
  private def interceptor_reaches?(holder : String, lines : Array(String), start : Int32, go_sources : Array(String)) : Bool
    own = function_text(lines, start)
    return true if own.matches?(INTERCEPTOR_MARK)
    call = /(?<![\w])(?:\w+\s*\.\s*)*#{Regex.escape(holder)}\s*\(/
    go_sources.any? do |file|
      content = read_file(file) || next false
      next false unless content.includes?(holder)
      found = false
      rpc_each_function(file) do |head, body|
        found = true if !head.includes?(" #{holder}(") && body.matches?(call) && (head + body).matches?(INTERCEPTOR_MARK)
      end
      found
    end
  end

  private def function_text(lines : Array(String), start : Int32) : String
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
