require "../ext/tree_sitter/tree_sitter"

# Which request-guard / extractor types can refuse an anonymous caller,
# read off their `impl FromRequest for X` (Rocket, actix-web) or
# `impl FromRequestParts<S> for X` (axum) definitions instead of their
# names.
#
# A type refuses when its impl can answer 401/403 (`Status::Unauthorized`,
# `StatusCode::FORBIDDEN`, actix `ErrorUnauthorized`, or a `macro_rules!`
# whose body does, or an error variant its `ResponseError::status_code`
# maps to 401/403: `Err(MyError::IncorrectLogin)` after
# `MyError::IncorrectLogin => StatusCode::UNAUTHORIZED`), or forwards the
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
  # A match arm of a `ResponseError::status_code` body mapping an error
  # variant to 401/403.
  STATUS_ARM_RE = /^[ \t]*([^\n=]+?)\s*=>\s*(?:[\w:]+::)?StatusCode::(?:UNAUTHORIZED|FORBIDDEN)\b/m
  VARIANT_RE    = /\b(\w+::\w+)\s*(?:\(|\{|\||$)/
  MAX_DEPTH     = 256

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
    getter refusing_variants = Set(String).new
  end

  def self.scan(source : String, facts : Facts) : Nil
    if source.includes?("fn status_code")
      # ponytail: a text slice from `fn status_code` to the next `fn`, so the
      # arms inside a `macro_rules!` / `cfg_select!` body are read too.
      source.split(/\bfn\s+(?=status_code\b)/).skip(1).each do |body|
        body.split(/\bfn\s/, 2).first.scan(STATUS_ARM_RE) do |arm|
          arm[1].scan(VARIANT_RE) { |v| facts.refusing_variants << variant_key(v[1]) }
        end
      end
    end
    return unless source.matches?(EVIDENCE_RE)
    Noir::TreeSitter.parse_rust(source) do |root|
      collect(root, source, facts, 0)
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

  private def self.collect(node : LibTreeSitter::TSNode, source : String, facts : Facts, depth : Int32)
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
          sites_in(body, source, nil, sites, 0)
          facts.impls << Impl.new(leaf, sites)
        end
        return
      end
    end
    Noir::TreeSitter.each_named_child(node) { |child| collect(child, source, facts, depth + 1) }
  end

  private def self.guard_called(text : String) : String?
    m = text.match(GUARD_CALL_RE) || return
    m[1]? || m[2]?
  end

  private def self.sites_in(node : LibTreeSitter::TSNode, source : String, cond : String?,
                            sites : Array(Site), depth : Int32)
    return if depth > MAX_DEPTH
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
      sites << Site.new(SiteKind::Variant, variant_key(text), cond) if text.includes?("::")
      return
    when "try_expression"
      if called = guard_called(Noir::TreeSitter.node_text(node, source))
        sites << Site.new(SiteKind::Delegate, called, cond)
      end
    when "let_declaration"
      alternative = Noir::TreeSitter.field(node, "alternative")
      value = Noir::TreeSitter.field(node, "value")
      Noir::TreeSitter.each_named_child(node) do |child|
        branch = cond
        if alternative && same?(child, alternative) && value
          branch = guard_called(Noir::TreeSitter.node_text(value, source)) || cond
        end
        sites_in(child, source, branch, sites, depth + 1)
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
        sites_in(child, source, branch, sites, depth + 1)
      end
      return
    when "match_expression"
      value = Noir::TreeSitter.field(node, "value")
      on = value ? guard_called(Noir::TreeSitter.node_text(value, source)) : nil
      value.try { |v| sites_in(v, source, cond, sites, depth + 1) }
      if on && (block = Noir::TreeSitter.field(node, "body"))
        Noir::TreeSitter.each_named_child(block) do |arm|
          pattern = Noir::TreeSitter.field(arm, "pattern")
          success = pattern && Noir::TreeSitter.node_text(pattern, source).strip.matches?(SUCCESS_ARM_RE)
          sites_in(arm, source, success ? cond : on, sites, depth + 1)
        end
        return
      end
      if block = Noir::TreeSitter.field(node, "body")
        sites_in(block, source, cond, sites, depth + 1)
      end
      return
    end
    Noir::TreeSitter.each_named_child(node) { |child| sites_in(child, source, cond, sites, depth + 1) }
  end

  # A `Self::Variant => StatusCode::UNAUTHORIZED` arm names its enum only
  # through the impl it sits in, so it matches that variant of any enum.
  private def self.refusing_variant?(name : String?, facts : Facts) : Bool
    return false unless name
    facts.refusing_variants.includes?(name) || facts.refusing_variants.includes?("Self::#{name.split("::").last}")
  end

  # `crate::error::MyError::Variant` -> `MyError::Variant`.
  private def self.variant_key(path : String) : String
    path.gsub(/\s+/, "").split("::").last(2).join("::")
  end

  private def self.same?(a : LibTreeSitter::TSNode, b : LibTreeSitter::TSNode) : Bool
    LibTreeSitter.ts_node_start_byte(a) == LibTreeSitter.ts_node_start_byte(b) &&
      LibTreeSitter.ts_node_end_byte(a) == LibTreeSitter.ts_node_end_byte(b)
  end
end
