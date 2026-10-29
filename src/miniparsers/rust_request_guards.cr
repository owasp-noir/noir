require "../ext/tree_sitter/tree_sitter"

# Which request-guard / extractor types can refuse an anonymous caller,
# read off their `impl FromRequest for X` (Rocket, actix-web) or
# `impl FromRequestParts<S> for X` (axum) definitions instead of their
# names.
#
# A type refuses when its impl can answer 401/403 (`Status::Unauthorized`,
# `StatusCode::FORBIDDEN`, actix `ErrorUnauthorized`, or a `macro_rules!`
# whose body does, or returns as its error a variant that
# `fn status_code` maps to 401/403: `Err(MyError::IncorrectLogin)`
# / `.ok_or(MyError::IncorrectLogin)` after
# `MyError::IncorrectLogin => StatusCode::UNAUTHORIZED`; `into_response`
# and any `&self` method returning a `StatusCode`, such as
# `fn client_status_and_error(&self) -> (StatusCode, ClientError)`, map
# variants the same way), or forwards the
# failure of a type that refuses
# (`try_outcome!(Headers::from_request(req).await)`, `X::from_request_parts(..).await?`).
# A refusal that only fires when another in-crate guard fails
# (`let Outcome::Success(ip) = ClientIp::from_request(req).await else { 401 }`)
# counts only if that guard itself refuses, so a wrapper around a guard
# that never fails is not a guard.
#
# No file I/O: callers feed source text to `scan` and combine the results.
module Noir::RustRequestGuards
  REFUSAL_RE     = /\bStatus::(?:Unauthorized|Forbidden)\b|\bStatusCode::(?:UNAUTHORIZED|FORBIDDEN)\b|\bError(?:Unauthorized|Forbidden)\b/
  GUARD_CALL_RE  = /(\w+)(?:\s*::\s*<[^<>]*>)?\s*::\s*from_request(?:_parts)?\s*\(|\bguard\s*::\s*<\s*(?:\w+::)*(\w+)/
  TRAIT_RE       = /\A(?:\w+::)*FromRequest(?:Parts)?\b/
  SUCCESS_ARM_RE = /\A(?:(?:\w+::)*Outcome::)?(?:Success|Ok)\s*\(/
  EVIDENCE_RE    = /\bFromRequest|macro_rules!/
  # ponytail: a status mapping is read off its signature, not its callers;
  # a `&self -> StatusCode` helper nothing calls still maps its variants.
  STATUS_FN_RE   = /\bfn\s+(?:status_code|into_response)\b|\bfn\s+\w+\s*\(\s*&?\s*(?:mut\s+)?self\b[^)]*\)\s*->\s*[^{;]*\bStatusCode\b/
  AUTH_STATUS_RE = /\bStatusCode::(?:UNAUTHORIZED|FORBIDDEN)\b/
  ANY_STATUS_RE  = /\bStatusCode::[A-Z]\w*/
  # An enum path in a match pattern: `AppError::NotLoggedIn`, `NotLoggedIn`.
  PATTERN_PATH_RE = /(?<![\w:])((?:[A-Za-z_]\w*::)*[A-Z]\w*)(?![\w:])/
  VARIANT_PATH_RE = /\A(?:\w+::)*[A-Z]\w*\z/
  ENUM_GLOB_RE    = /\buse\s+(?:[\w:]+::)?([A-Z]\w*)::\*\s*;/
  IMPL_FOR_RE     = /\bimpl\b[^{};]*?\bfor\s+(?:\w+::)*(\w+)/
  # `impl Type`, `impl crate::Type`, `impl Type<T>`, `impl<T> Type<T>`.
  INHERENT_IMPL_RE = /\Aimpl(?:\s*<[^;{}]*>)?\s+(?:\w+::)*(\w+)(?:\s*<[^;{}]*>)?\s*\{/
  # Methods whose argument becomes the `Err` of the value they return.
  ERR_ADAPTERS = {"ok_or", "ok_or_else", "map_err"}
  MAX_DEPTH    = 256

  enum SiteKind
    Direct
    Macro
    Delegate
    Variant
  end

  # A place in a guard impl that can end the request: what it is, and the
  # in-crate guard whose failure it is conditional on (nil = unconditional).
  record Site, kind : SiteKind, name : String?, condition : String?
  record Impl, type : String, sites : Array(Site)

  class Facts
    getter impls = [] of Impl
    getter refusing_macros = Set(String).new
    # `Enum::Variant` keys a `status_code` arm maps to 401/403, and those
    # some arm maps to another status (a key in both is not trusted).
    getter refusing_variants = Set(String).new
    getter other_variants = Set(String).new
  end

  # Per-file state for walking a guard impl.
  private record Walk, source : String, sites : Array(Site), enum_globs : Array(String)

  def self.scan(source : String, facts : Facts) : Nil
    globs = source.includes?("::*") ? source.scan(ENUM_GLOB_RE).map(&.[1]).uniq! : [] of String
    collect_status_arms(source, globs, facts) if source.matches?(STATUS_FN_RE)
    return unless source.matches?(EVIDENCE_RE)
    Noir::TreeSitter.parse_rust(source) do |root|
      collect(root, source, globs, facts, 0)
    end
  end

  # `{type => refuses?}` for every type whose impls agree.
  def self.resolve(facts : Facts) : Hash(String, Bool)
    known = facts.impls.map(&.type).to_set
    guards = Set(String).new
    loop do
      added = false
      facts.impls.each do |impl|
        next if guards.includes?(impl.type)
        next unless impl.sites.any? { |site| refuses?(site, guards, known, facts) }
        guards << impl.type
        added = true
      end
      break unless added
    end

    verdicts = {} of String => Bool
    mixed = Set(String).new
    facts.impls.each do |impl|
      verdict = impl.sites.any? { |site| refuses?(site, guards, known, facts) }
      if verdicts.has_key?(impl.type) && verdicts[impl.type] != verdict
        mixed << impl.type
      end
      verdicts[impl.type] = verdict
    end
    mixed.each { |name| verdicts.delete(name) }
    verdicts
  end

  # Leaf type names of a fn's parameters that are required guards, keyed
  # by the fn name's 1-based line. `Option<X>` / `Result<X, E>` parameters
  # never refuse the request, so they are left out.
  def self.handler_param_types(source : String) : Hash(Int32, Array(String))
    result = {} of Int32 => Array(String)
    Noir::TreeSitter.parse_rust(source) do |root|
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name = Noir::TreeSitter.field(node, "name") || next
        params = Noir::TreeSitter.field(node, "parameters") || next
        types = [] of String
        Noir::TreeSitter.each_named_child(params) do |param|
          next unless Noir::TreeSitter.node_type(param) == "parameter"
          type = Noir::TreeSitter.field(param, "type") || next
          leaf = type_leaf(Noir::TreeSitter.node_text(type, source)) || next
          types << leaf unless leaf == "Option" || leaf == "Result"
        end
        result[Noir::TreeSitter.node_start_row(name) + 1] = types
      end
    end
    result
  end

  def self.type_leaf(text : String) : String?
    stripped = text.strip.lchop('&').strip.sub(/\A'\w+\s+/, "").sub(/\Amut\s+/, "")
    stripped.match(/\A(?:\w+::)*(\w+)/).try(&.[1])
  end

  private def self.refuses?(site : Site, guards : Set(String), known : Set(String), facts : Facts) : Bool
    fires = case site.kind
            in .direct?   then true
            in .macro?    then facts.refusing_macros.includes?(site.name)
            in .delegate? then guards.includes?(site.name)
            in .variant?  then refusing_variant?(site.name, facts)
            end
    return false unless fires
    cond = site.condition
    cond.nil? || guards.includes?(cond) || !known.includes?(cond)
  end

  # The match arms of every status-mapping fn body (`STATUS_FN_RE`). The
  # body is cut out by its braces and parsed on its own, so a
  # `ResponseError` impl inside a `macro_rules!` / `cfg_select!` token tree
  # is read as well.
  private def self.collect_status_arms(source : String, globs : Array(String), facts : Facts)
    offset = 0
    while m = source.match(STATUS_FN_RE, offset)
      open = source.index('{', m.end) || break
      close = matching_brace(source, open) || break
      offset = close
      impl_type = status_self_type(source, m.begin)
      body = "fn status_code() #{source[open..close]}"
      Noir::TreeSitter.parse_rust(body) do |root|
        Noir::TreeSitter.walk(root) do |arm|
          next unless Noir::TreeSitter.node_type(arm) == "match_arm"
          pattern = Noir::TreeSitter.field(arm, "pattern") || next
          value = Noir::TreeSitter.field(arm, "value") || next
          text = Noir::TreeSitter.node_text(value, body)
          # An arm naming no status (`=> return (self.status_code(), ..)`,
          # `=> log::error!(..)`) leaves the variant to another arm.
          next unless text.matches?(ANY_STATUS_RE)
          target = text.matches?(AUTH_STATUS_RE) ? facts.refusing_variants : facts.other_variants
          Noir::TreeSitter.node_text(pattern, body).scan(PATTERN_PATH_RE) do |path|
            variant_keys(path[1], impl_type, globs).each { |key| target << key }
          end
        end
      end
    end
  end

  # The impl whose body contains `fn_at`. A later header replaces an earlier one,
  # so `impl Error` is not overridden by an earlier `impl Trait for Other`.
  private def self.status_self_type(source : String, fn_at : Int32) : String?
    chosen : String? = nil
    offset = 0
    while header = source.match(/\bimpl\b/, offset)
      break if header.begin >= fn_at
      offset = header.end
      if type_name = impl_type_enclosing(source, header.begin, fn_at)
        chosen = type_name
      end
    end
    chosen
  end

  private def self.impl_type_enclosing(source : String, at : Int32, fn_at : Int32) : String?
    rest = source[at, source.size - at]
    type_name : String? = nil
    brace : Int32? = nil
    if (found = rest.match(IMPL_FOR_RE)) && found.begin == 0
      if open = rest.index('{', found.end)
        type_name = found[1]
        brace = open
      end
    end
    if type_name.nil? && (found = rest.match(INHERENT_IMPL_RE))
      type_name = found[1]
      brace = found.end - 1
    end
    return unless (name = type_name) && (open = brace)
    abs = at + open
    close = matching_brace(source, abs) || return
    return unless abs < fn_at && fn_at < close
    name
  end

  # Index of the `}` closing the `{` at `open`, skipping string literals.
  private def self.matching_brace(source : String, open : Int32) : Int32?
    depth = 0
    in_string = false
    escaped = false
    (open...source.size).each do |i|
      c = source[i]
      if in_string
        if escaped
          escaped = false
        elsif c == '\\'
          escaped = true
        elsif c == '"'
          in_string = false
        end
      elsif c == '"'
        in_string = true
      elsif c == '{'
        depth += 1
      elsif c == '}'
        depth -= 1
        return i if depth == 0
      end
    end
    nil
  end

  # `Enum::Variant` keys a path names: `a::AppError::X` -> `AppError::X`,
  # `Self::X` -> `<self_type>::X`, a bare `X` -> `E::X` for each
  # `use E::*` of the file.
  private def self.variant_keys(path : String, self_type : String?, globs : Array(String)) : Array(String)
    parts = path.gsub(/\s+/, "").split("::")
    return globs.map { |enum_name| "#{enum_name}::#{parts[0]}" } if parts.size == 1
    if parts[-2] == "Self"
      return self_type ? ["#{self_type}::#{parts[-1]}"] : [] of String
    end
    [parts.last(2).join("::")]
  end

  private def self.collect(node : LibTreeSitter::TSNode, source : String, globs : Array(String), facts : Facts, depth : Int32)
    return if depth > MAX_DEPTH
    case Noir::TreeSitter.node_type(node)
    when "macro_definition"
      if (name = Noir::TreeSitter.field(node, "name")) && Noir::TreeSitter.node_text(node, source).matches?(REFUSAL_RE)
        facts.refusing_macros << Noir::TreeSitter.node_text(name, source)
      end
      return
    when "impl_item"
      trait = Noir::TreeSitter.field(node, "trait")
      type = Noir::TreeSitter.field(node, "type")
      body = Noir::TreeSitter.field(node, "body")
      if trait && type && body && Noir::TreeSitter.node_text(trait, source).matches?(TRAIT_RE)
        if leaf = type_leaf(Noir::TreeSitter.node_text(type, source))
          sites = [] of Site
          sites_in(body, Walk.new(source, sites, globs), nil, false, false, 0)
          facts.impls << Impl.new(leaf, sites)
        end
        return
      end
    end
    Noir::TreeSitter.each_named_child(node) { |child| collect(child, source, globs, facts, depth + 1) }
  end

  private def self.guard_called(text : String) : String?
    m = text.match(GUARD_CALL_RE) || return
    m[1]? || m[2]?
  end

  # `err`: the node is the error a returned `Err(...)` / `.ok_or(...)`
  # carries. `in_let`: the node is a `let` initializer, whose `Err` is
  # bound rather than returned unless a `?` propagates it.
  private def self.sites_in(node : LibTreeSitter::TSNode, walk : Walk, cond : String?,
                            err : Bool, in_let : Bool, depth : Int32)
    return if depth > MAX_DEPTH
    source = walk.source
    sites = walk.sites
    case Noir::TreeSitter.node_type(node)
    when "macro_invocation"
      text = Noir::TreeSitter.node_text(node, source)
      sites << Site.new(SiteKind::Direct, nil, cond) if text.matches?(REFUSAL_RE)
      if called = guard_called(text)
        sites << Site.new(SiteKind::Delegate, called, cond)
      end
      if name = Noir::TreeSitter.field(node, "macro")
        sites << Site.new(SiteKind::Macro, Noir::TreeSitter.node_text(name, source).split("::").last, cond)
      end
      return
    when "scoped_identifier", "identifier"
      text = Noir::TreeSitter.node_text(node, source)
      sites << Site.new(SiteKind::Direct, nil, cond) if text.matches?(REFUSAL_RE)
      if err && text.matches?(VARIANT_PATH_RE)
        # `Self::X` in a guard impl names the guard type, not an error.
        variant_keys(text, nil, walk.enum_globs).each do |key|
          sites << Site.new(SiteKind::Variant, key, cond)
        end
      end
      return
    when "call_expression"
      fn = Noir::TreeSitter.field(node, "function")
      args = Noir::TreeSitter.field(node, "arguments")
      if fn && args
        fn_type = Noir::TreeSitter.node_type(fn)
        if fn_type == "identifier" && Noir::TreeSitter.node_text(fn, source) == "Err"
          sites_in(args, walk, cond, !in_let, in_let, depth + 1)
          return
        end
        field = fn_type == "field_expression" ? Noir::TreeSitter.field(fn, "field") : nil
        if field && ERR_ADAPTERS.includes?(Noir::TreeSitter.node_text(field, source))
          Noir::TreeSitter.field(fn, "value").try { |v| sites_in(v, walk, cond, err, in_let, depth + 1) }
          sites_in(args, walk, cond, !in_let, in_let, depth + 1)
          return
        end
      end
    when "try_expression"
      if called = guard_called(Noir::TreeSitter.node_text(node, source))
        sites << Site.new(SiteKind::Delegate, called, cond)
      end
      Noir::TreeSitter.each_named_child(node) { |child| sites_in(child, walk, cond, err, false, depth + 1) }
      return
    when "match_arm", "let_condition"
      pattern = Noir::TreeSitter.field(node, "pattern")
      Noir::TreeSitter.each_named_child(node) do |child|
        next if pattern && same?(child, pattern)
        sites_in(child, walk, cond, err, in_let, depth + 1)
      end
      return
    when "let_declaration"
      alternative = Noir::TreeSitter.field(node, "alternative")
      value = Noir::TreeSitter.field(node, "value")
      pattern = Noir::TreeSitter.field(node, "pattern")
      Noir::TreeSitter.each_named_child(node) do |child|
        next if pattern && same?(child, pattern)
        branch = cond
        if alternative && same?(child, alternative) && value
          branch = guard_called(Noir::TreeSitter.node_text(value, source)) || cond
        end
        bound = value ? same?(child, value) : false
        sites_in(child, walk, branch, bound ? false : err, bound || in_let, depth + 1)
      end
      return
    when "if_expression"
      condition = Noir::TreeSitter.field(node, "condition")
      alternative = Noir::TreeSitter.field(node, "alternative")
      Noir::TreeSitter.each_named_child(node) do |child|
        branch = cond
        if alternative && condition && same?(child, alternative)
          branch = guard_called(Noir::TreeSitter.node_text(condition, source)) || cond
        end
        sites_in(child, walk, branch, err, in_let, depth + 1)
      end
      return
    when "match_expression"
      value = Noir::TreeSitter.field(node, "value")
      on = value ? guard_called(Noir::TreeSitter.node_text(value, source)) : nil
      value.try { |v| sites_in(v, walk, cond, false, in_let, depth + 1) }
      if on && (block = Noir::TreeSitter.field(node, "body"))
        Noir::TreeSitter.each_named_child(block) do |arm|
          pattern = Noir::TreeSitter.field(arm, "pattern")
          success = pattern && Noir::TreeSitter.node_text(pattern, source).strip.matches?(SUCCESS_ARM_RE)
          sites_in(arm, walk, success ? cond : on, err, in_let, depth + 1)
        end
        return
      end
      if block = Noir::TreeSitter.field(node, "body")
        sites_in(block, walk, cond, err, in_let, depth + 1)
      end
      return
    end
    Noir::TreeSitter.each_named_child(node) { |child| sites_in(child, walk, cond, err, in_let, depth + 1) }
  end

  # ponytail: variants are keyed `Enum::Variant` scan-wide, not by the
  # enum's resolved path; a key any `status_code` maps to another status is
  # dropped, so only same-named enums that disagree silently collide.
  private def self.refusing_variant?(name : String?, facts : Facts) : Bool
    return false unless name
    facts.refusing_variants.includes?(name) && !facts.other_variants.includes?(name)
  end

  private def self.same?(a : LibTreeSitter::TSNode, b : LibTreeSitter::TSNode) : Bool
    LibTreeSitter.ts_node_start_byte(a) == LibTreeSitter.ts_node_start_byte(b) &&
      LibTreeSitter.ts_node_end_byte(a) == LibTreeSitter.ts_node_end_byte(b)
  end
end
