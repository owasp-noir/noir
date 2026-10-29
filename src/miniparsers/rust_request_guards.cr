require "../ext/tree_sitter/tree_sitter"
require "../utils/c_comments"
require "./rust_use_imports"

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
# variants the same way, read where the enum is defined: its file when the
# guard's file defines it, else its crate), or forwards the
# failure of a type that refuses
# (`try_outcome!(Headers::from_request(req).await)`, `X::from_request_parts(..).await?`).
# A refusal that only fires when another in-crate guard fails
# (`let Outcome::Success(ip) = ClientIp::from_request(req).await else { 401 }`)
# counts only if that guard itself refuses, so a wrapper around a guard
# that never fails is not a guard.
#
# A redirect to a login page (`Redirect::to("/login")`, a `SEE_OTHER` with
# a `/login` location) refuses like a 401.
#
# No file I/O: callers feed source text (and its path) to `scan` and
# combine the results.
module Noir::RustRequestGuards
  REFUSAL_RE     = /\bStatus::(?:Unauthorized|Forbidden)\b|\bStatusCode::(?:UNAUTHORIZED|FORBIDDEN)\b|\bError(?:Unauthorized|Forbidden)\b/
  GUARD_CALL_RE  = /(\w+)(?:\s*::\s*<[^<>]*>)?\s*::\s*from_request(?:_parts)?\s*\(|\bguard\s*::\s*<\s*(?:\w+::)*(\w+)/
  TRAIT_RE       = /\A(?:\w+::)*FromRequest(?:Parts)?\b/
  SUCCESS_ARM_RE = /\A(?:(?:\w+::)*Outcome::)?(?:Success|Ok)\s*\(/
  EVIDENCE_RE    = /\bFromRequest|macro_rules!/
  # ponytail: a status mapping is read off its signature, not its callers;
  # a `&self -> StatusCode` helper nothing calls still maps its variants.
  STATUS_FN_RE   = /\bfn\s+(?:(status_code)|into_response)\b|\bfn\s+\w+\s*\(\s*&?\s*(?:mut\s+)?self\b[^)]*\)\s*->\s*[^{;]*\bStatusCode\b/
  AUTH_STATUS_RE = /\bStatusCode::(?:UNAUTHORIZED|FORBIDDEN)\b/
  # A status or a redirect (any 3xx).
  ANY_STATUS_RE = /\bStatusCode::[A-Z]\w*|\bRedirect::\w+\s*\(/
  # `Redirect::to("/login")`, `(header::LOCATION, "/signin")`: the target
  # literal names a login page and carries no `error=` (an OAuth callback
  # sending a failed login back is not a refusal of the caller).
  LOGIN_REDIRECT_RE = /(?:\bRedirect::\w+\s*\(\s*|(?:\bLOCATION|"(?i:location)")\s*,\s*)"(?![^"]*\berror=)[^"]*?(?<![A-Za-z])(?i:log_?in|sign_?in)/
  ENUM_DEF_RE       = /\benum\s+([A-Z]\w*)/
  IMPL_KEYWORD_RE   = /\bimpl\b/
  CRATE_USE_RE      = /\buse\s+crate::[^;]*;/
  # A raw string (`r#"say "hi""#`) or a char literal (`'"'`, `'\''`,
  # `'\u{1F600}'`), neither of which the C-style stripper can read; not a
  # lifetime (`'a`).
  RUST_LITERAL_RE = /(?<![\w'])b?r(#*)"[\s\S]*?"\1|'(?:[^'\\\n]|\\(?:u\{[0-9a-fA-F]{1,6}\}|x[0-9a-fA-F]{2}|.))'/
  # An enum path in a match pattern: `AppError::NotLoggedIn`, `NotLoggedIn`.
  PATTERN_PATH_RE = /(?<![\w:])((?:[A-Za-z_]\w*::)*[A-Z]\w*)(?![\w:])/
  VARIANT_PATH_RE = /\A(?:\w+::)*[A-Z]\w*\z/
  ENUM_GLOB_RE    = /\buse\s+(?:[\w:]+::)?([A-Z]\w*)::\*\s*;/
  IMPL_FOR_RE     = /\bimpl\b[^{};]*?\bfor\s+(?:\w+::)*(\w+)/
  # `impl Type`, `impl crate::Type`, `impl Type<T>`, `impl<T> Type<T>`.
  # Both impl patterns are matched anchored at an `impl` keyword.
  INHERENT_IMPL_RE = /impl(?:\s*<[^;{}]*>)?\s+(?:\w+::)*(\w+)(?:\s*<[^;{}]*>)?\s*\{/
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
  # `file` / `crate`: where the impl is, to read its error variants there.
  record Impl, type : String, sites : Array(Site), file : String, crate : String
  # An `impl` block's type and the byte offsets of its braces.
  private record ImplSpan, type : String, open : Int32, close : Int32

  class Facts
    getter impls = [] of Impl
    getter refusing_macros = Set(String).new
    # `Enum::Variant` keys a `status_code` arm maps to 401/403, and those
    # some arm maps to another status (a key in both is not trusted).
    getter refusing_variants = Set(String).new
    getter other_variants = Set(String).new
    # The same arms from every status-mapping fn, keyed `scope|Enum::Variant`
    # with scope `f:<file>` and `c:<crate dir>`; `scope|Enum` for an enum
    # some arm there maps, and for one whose `match self` has a catch-all
    # arm (`_ =>`) answering another status.
    getter scoped_refusing = Set(String).new
    getter scoped_other = Set(String).new
    getter scoped_enums = Set(String).new
    getter scoped_catch_all = Set(String).new
    # `crate|Enum` => the files of that crate that define `enum Enum`.
    getter enum_files = Hash(String, Set(String)).new
    # A guard impl file's `use crate::...;` statements, parsed for their
    # names (`Error` => `crate::error::Error`) only when an enum is ambiguous.
    getter crate_uses = Hash(String, String).new
    getter crate_use_names = Hash(String, Hash(String, String)).new
  end

  # Per-file state for walking a guard impl.
  private record Walk, source : String, sites : Array(Site), enum_globs : Array(String)

  def self.scan(source : String, facts : Facts, path : String = "") : Nil
    crate = crate_dir(path)
    globs = source.includes?("::*") ? source.scan(ENUM_GLOB_RE).map(&.[1]).uniq! : [] of String
    status_fn = source.matches?(STATUS_FN_RE)
    if status_fn || source.includes?("enum")
      # `'` also opens a lifetime, so only `"` opens a string here.
      code = Noir::CComments.strip(blank_literals(source), quotes: %("))
      code.scan(ENUM_DEF_RE) { |m| (facts.enum_files["#{crate}|#{m[1]}"] ||= Set(String).new) << path }
      collect_status_arms(code, globs, facts, path, crate) if status_fn
    end
    return unless source.matches?(EVIDENCE_RE)
    if source.includes?("crate::")
      facts.crate_uses[path] = source.scan(CRATE_USE_RE).join('\n', &.[0])
    end
    Noir::TreeSitter.parse_rust(source) do |root|
      collect(root, source, globs, facts, path, crate, 0)
    end
  end

  # `source` with its raw strings as `""` and its char literals as `' '`.
  private def self.blank_literals(source : String) : String
    return source unless source.includes?('\'') || source.includes?("r#") || source.includes?("r\"")
    utf = source.valid_encoding? ? Regex::MatchOptions::NO_UTF_CHECK : Regex::MatchOptions::None
    bytes = source.to_slice
    String.build(source.bytesize) do |io|
      pos = 0
      while m = RUST_LITERAL_RE.match_at_byte_index(source, pos, utf)
        io.write(bytes[pos, m.byte_begin - pos])
        io << (m[0].starts_with?('\'') ? "' '" : %(""))
        pos = m.byte_end
      end
      io.write(bytes[pos, bytes.size - pos])
    end
  end

  # The crate dir of a file: its path up to the last `src` dir.
  private def self.crate_dir(path : String) : String
    sep = File::SEPARATOR
    if idx = path.rindex("#{sep}src#{sep}")
      path[0, idx]
    elsif path.starts_with?("src#{sep}")
      ""
    else
      File.dirname(path)
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
        next unless impl.sites.any? { |site| refuses?(site, impl, guards, known, facts) }
        guards << impl.type
        added = true
      end
      break unless added
    end

    verdicts = {} of String => Bool
    mixed = Set(String).new
    facts.impls.each do |impl|
      verdict = impl.sites.any? { |site| refuses?(site, impl, guards, known, facts) }
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

  private def self.refuses?(site : Site, impl : Impl, guards : Set(String), known : Set(String), facts : Facts) : Bool
    fires = case site.kind
            in .direct?   then true
            in .macro?    then facts.refusing_macros.includes?(site.name)
            in .delegate? then guards.includes?(site.name)
            in .variant?  then refusing_variant?(site.name, impl, facts)
            end
    return false unless fires
    cond = site.condition
    cond.nil? || guards.includes?(cond) || !known.includes?(cond)
  end

  # The match arms of every status-mapping fn body (`STATUS_FN_RE`). The
  # body is cut out by its braces and parsed on its own, so a
  # `ResponseError` impl inside a `macro_rules!` / `cfg_select!` token tree
  # is read as well. `fn status_code` arms also count scan-wide.
  private def self.collect_status_arms(source : String, globs : Array(String), facts : Facts, file : String, crate : String)
    bytes = source.to_slice
    # PCRE2 re-validates the whole subject as UTF-8 on every match unless told not to.
    utf = source.valid_encoding? ? Regex::MatchOptions::NO_UTF_CHECK : Regex::MatchOptions::None
    spans = impl_spans(source, bytes, utf)
    scopes = {"f:#{file}", "c:#{crate}"}
    offset = 0
    while m = STATUS_FN_RE.match_at_byte_index(source, offset, utf)
      open = bytes.index('{'.ord.to_u8, m.byte_end) || break
      close = matching_brace(bytes, open) || break
      offset = close
      legacy = !m[1]?.nil?
      impl_type = enclosing_impl(spans, m.byte_begin)
      body = "fn status_code() #{String.new(bytes[open, close - open + 1])}"
      Noir::TreeSitter.parse_rust(body) do |root|
        Noir::TreeSitter.walk(root) do |arm|
          next unless Noir::TreeSitter.node_type(arm) == "match_arm"
          pattern = Noir::TreeSitter.field(arm, "pattern") || next
          value = Noir::TreeSitter.field(arm, "value") || next
          text = Noir::TreeSitter.node_text(value, body)
          redirect = text.matches?(LOGIN_REDIRECT_RE)
          # An arm naming no status (`=> return (self.status_code(), ..)`,
          # `=> log::error!(..)`) leaves the variant to another arm.
          next unless redirect || text.matches?(ANY_STATUS_RE)
          refusing = redirect || text.matches?(AUTH_STATUS_RE)
          paths = Noir::TreeSitter.node_text(pattern, body).scan(PATTERN_PATH_RE).map(&.[1])
          if paths.empty?
            if impl_type && !refusing && self_match?(arm, body)
              scopes.each do |scope|
                facts.scoped_catch_all << "#{scope}|#{impl_type}"
                facts.scoped_enums << "#{scope}|#{impl_type}"
              end
            end
            next
          end
          paths.each do |path|
            variant_keys(path, impl_type, globs).each do |key|
              (refusing ? facts.refusing_variants : facts.other_variants) << key if legacy
              enum_name = key.rpartition("::")[0]
              scopes.each do |scope|
                (refusing ? facts.scoped_refusing : facts.scoped_other) << "#{scope}|#{key}"
                facts.scoped_enums << "#{scope}|#{enum_name}"
              end
            end
          end
        end
      end
    end
  end

  # The arm is one of a `match self` / `match *self`.
  private def self.self_match?(arm : LibTreeSitter::TSNode, source : String) : Bool
    block = Noir::TreeSitter.parent(arm) || return false
    match = Noir::TreeSitter.parent(block) || return false
    value = Noir::TreeSitter.field(match, "value") || return false
    Noir::TreeSitter.node_text(value, source).delete("&*").strip == "self"
  end

  # Every `impl` block of the file, in header order. Each impl pattern is
  # matched anchored at its `impl` keyword, so this is one pass.
  private def self.impl_spans(source : String, bytes : Bytes, utf : Regex::MatchOptions) : Array(ImplSpan)
    spans = [] of ImplSpan
    offset = 0
    while header = IMPL_KEYWORD_RE.match_at_byte_index(source, offset, utf)
      at = header.byte_begin
      offset = header.byte_end
      type_name : String? = nil
      open : Int32? = nil
      if found = IMPL_FOR_RE.match_at_byte_index(source, at, utf | Regex::MatchOptions::ANCHORED)
        if brace = bytes.index('{'.ord.to_u8, found.byte_end)
          type_name = found[1]
          open = brace
        end
      end
      if type_name.nil? && (found = INHERENT_IMPL_RE.match_at_byte_index(source, at, utf | Regex::MatchOptions::ANCHORED))
        type_name = found[1]
        open = found.byte_end - 1
      end
      next unless type_name && open
      close = matching_brace(bytes, open) || next
      spans << ImplSpan.new(type_name, open, close)
    end
    spans
  end

  # The type of the innermost (latest-opened) impl whose braces hold
  # `at`, so `impl Error` is not overridden by an earlier
  # `impl Trait for Other`.
  # ponytail: walks back over earlier impls until one encloses; linear per
  # fn only for a status fn outside every impl (a trait default).
  private def self.enclosing_impl(spans : Array(ImplSpan), at : Int32) : String?
    idx = (spans.bsearch_index { |span| span.open >= at } || spans.size) - 1
    while idx >= 0
      span = spans[idx]
      return span.type if span.close > at
      idx -= 1
    end
    nil
  end

  # Byte offset of the `}` closing the `{` at `open`, skipping string and
  # char literals.
  private def self.matching_brace(bytes : Bytes, open : Int32) : Int32?
    depth = 0
    in_string = false
    escaped = false
    i = open
    while i < bytes.size
      c = bytes[i]
      if in_string
        if escaped
          escaped = false
        elsif c == '\\'.ord
          escaped = true
        elsif c == '"'.ord
          in_string = false
        end
      elsif c == '"'.ord
        in_string = true
      elsif c == '\''.ord && i + 2 < bytes.size && bytes[i + 2] == '\''.ord
        i += 2
      elsif c == '{'.ord
        depth += 1
      elsif c == '}'.ord
        depth -= 1
        return i if depth == 0
      end
      i += 1
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

  private def self.collect(node : LibTreeSitter::TSNode, source : String, globs : Array(String), facts : Facts,
                           file : String, crate : String, depth : Int32)
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
          facts.impls << Impl.new(leaf, sites, file, crate)
        end
        return
      end
    end
    Noir::TreeSitter.each_named_child(node) { |child| collect(child, source, globs, facts, file, crate, depth + 1) }
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
    when "struct_expression"
      # `Err(ApiError::Unauthorized { reason })`: the error is the name; the
      # field values are not.
      if err && (name = Noir::TreeSitter.field(node, "name"))
        text = Noir::TreeSitter.node_text(name, source)
        if text.matches?(VARIANT_PATH_RE)
          variant_keys(text, nil, walk.enum_globs).each do |key|
            sites << Site.new(SiteKind::Variant, key, cond)
          end
        end
      end
      Noir::TreeSitter.field(node, "body").try { |body| sites_in(body, walk, cond, false, in_let, depth + 1) }
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

  # A variant refuses as the mapping where its enum lives says: the guard
  # file's own when that file defines the enum, else its crate's when only
  # one file there defines it. A variant that mapping does not decide falls
  # back to the scan-wide `fn status_code` arms.
  # ponytail: scan-wide variants are keyed `Enum::Variant`, not by the
  # enum's resolved path; a key any `status_code` maps to another status is
  # dropped, so only same-named enums that disagree silently collide.
  private def self.refusing_variant?(name : String?, impl : Impl, facts : Facts) : Bool
    return false unless name
    enum_name = name.rpartition("::")[0]
    defs = facts.enum_files["#{impl.crate}|#{enum_name}"]?
    scope = if defs && defs.includes?(impl.file)
              "f:#{impl.file}"
            elsif defs.nil? || defs.size == 1
              "c:#{impl.crate}"
            elsif def_file = imported_def(defs, enum_name, impl, facts) || mapped_def(defs, enum_name, facts)
              "f:#{def_file}"
            end
    if scope && facts.scoped_enums.includes?("#{scope}|#{enum_name}")
      key = "#{scope}|#{name}"
      return false if facts.scoped_other.includes?(key)
      return true if facts.scoped_refusing.includes?(key)
      return false if facts.scoped_catch_all.includes?("#{scope}|#{enum_name}")
    end
    facts.refusing_variants.includes?(name) && !facts.other_variants.includes?(name)
  end

  # Of the crate files defining `enum_name`, the one the guard's file
  # `use`s it from (`use crate::error::Error` -> `src/error.rs` or
  # `src/error/mod.rs`).
  private def self.imported_def(defs : Set(String), enum_name : String, impl : Impl, facts : Facts) : String?
    uses = facts.crate_uses[impl.file]? || return
    names = facts.crate_use_names[impl.file] ||= Noir::RustUseImports.parse(uses).names
    full = names[enum_name]? || return
    return unless full.starts_with?("crate::")
    sep = File::SEPARATOR
    src = impl.crate.empty? ? "src" : "#{impl.crate}#{sep}src"
    mod = full.lchop("crate::").split("::")[0...-1]
    candidates = mod.empty? ? ["#{src}#{sep}lib.rs", "#{src}#{sep}main.rs"] : ["#{src}#{sep}#{mod.join(sep)}.rs", "#{src}#{sep}#{mod.join(sep)}#{sep}mod.rs"]
    defs.find { |file| candidates.includes?(file) }
  end

  # The only one of the crate files defining `enum_name` that also maps it.
  private def self.mapped_def(defs : Set(String), enum_name : String, facts : Facts) : String?
    mapped = defs.select { |file| facts.scoped_enums.includes?("f:#{file}|#{enum_name}") }
    mapped.size == 1 ? mapped.first : nil
  end

  private def self.same?(a : LibTreeSitter::TSNode, b : LibTreeSitter::TSNode) : Bool
    LibTreeSitter.ts_node_start_byte(a) == LibTreeSitter.ts_node_start_byte(b) &&
      LibTreeSitter.ts_node_end_byte(a) == LibTreeSitter.ts_node_end_byte(b)
  end
end
