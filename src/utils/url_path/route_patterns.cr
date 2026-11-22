module Noir::URLPath
  # Adapter grammars match the route as declared. The optimizer's whole-slot
  # matcher instead compares reports across frameworks. In particular a word
  # may start with a digit, and an identifier may match part of a segment.
  COLON_WORD                = /:(\w+)/
  COLON_IDENT               = /:([A-Za-z_]\w*)/
  COLON_ASCII               = /:([A-Za-z_][A-Za-z0-9_]*)/
  BRACE_WORD                = /\{(\w+)\}/
  BRACE_IDENT               = /\{([A-Za-z_]\w*)\}/
  BRACE_ASCII               = /\{([A-Za-z_][A-Za-z0-9_]*)\}/
  COLON_OR_STAR             = /[:*]([A-Za-z_]\w*)/
  BRACE_CATCH_ALL           = /\{\*?(\w+)\}/
  BRACE_CONVERTER           = /\{([A-Za-z_][A-Za-z0-9_]*)(?::[A-Za-z_][A-Za-z0-9_]*)?\}/
  BRACE_TYPED               = /\{([A-Za-z_][A-Za-z0-9_]*):[A-Za-z_][A-Za-z0-9_]*\}/
  BRACE_CONVERTER_FIRST     = /\{(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?([A-Za-z_][A-Za-z0-9_]*)\}/
  BRACE_CONSTRAINT          = /\{([^{}:]+):[^{}]+\}/
  COLON_TYPED               = /:([A-Za-z_]\w*)(?::[A-Za-z_]\w*)?/
  COLON_OPTIONAL            = /:([A-Za-z_]\w*)\??/
  ANGLE_PIPE                = /<([A-Za-z_]\w*)(?:\|[^>]*)?>/
  COLON_SEGMENT_ASCII       = /(?<=^|\/):([A-Za-z_][A-Za-z0-9_]*)/
  BRACE_TYPED_ASCII         = /\{([a-zA-Z_][a-zA-Z0-9_]*):[^}]+\}/
  BRACE_WITH_CONSTRAINT     = /\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[^}]+)?\}/
  BRACE_FLAT_CONSTRAINT     = /\{([A-Za-z_]\w*)(?::[^{}]*)?\}/
  BRACE_OPTIONAL_CONSTRAINT = /\{([a-zA-Z0-9_]+)\??(?::[^{}]+)?\}/
  COLON_ANGLE_CONSTRAINT    = /:(\w+)(?:<[^>]*>)?/
  ANGLE_NAME_TYPED          = /<([A-Za-z_][A-Za-z0-9_]*)(?::[^>]+)?>/
  ANGLE_WORD_TYPED          = /<(\w+)(?::[^>]+)?>/
  COLON_OR_STAR_ASCII       = /[:*]([A-Za-z_][A-Za-z0-9_]*)/
  COLON_STAR_HASH           = /[:*#]([A-Za-z_][A-Za-z0-9_]*)/
  DOLLAR_OPTIONAL_BRACES    = /\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/
  BRACE_OR_SPLAT            = /(?|\{([A-Za-z_][A-Za-z0-9_]*)(?::[^}]+)?\}|\*([A-Za-z_][A-Za-z0-9_]*))/
  BRACE_WORD_CONSTRAINT     = /\{(\w+)(?::[^}]+)?\}/
  BRACE_REST_IDENT          = /\{\**([A-Za-z_]\w*)\}/
  SLASH_SPLAT_IDENT         = %r{/\*([A-Za-z_]\w*)}
  BRACE_REST_WORD           = /\{\**(\w+)\}/
  ANGLE_WORD                = /<(\w+)>/
  BRACE_REST_PIPE           = /\{\**(\w+)(?:\|[^}]*)?\}/
  SPLAT_WORD                = /\*(\w+)/
  DOLLAR_REGEX              = /\$(\w+)<[^>]+>/
  NAMED_CAPTURE             = /\(\?<([A-Za-z_][A-Za-z0-9_]*)>/
  COLON_OR_STAR_HYPHEN      = /[:*]([A-Za-z_][\w\-]*)/
  COLON_DOTTED              = /:([A-Za-z_][A-Za-z0-9_.-]*)/
  BRACE_DOTTED              = /\{([A-Za-z_][A-Za-z0-9_.-]*)\}/
  DOLLAR_BRACED_IDENT       = /\$\{([A-Za-z_]\w*)\}/
  DOLLAR_IDENT              = /\$([A-Za-z_]\w*)/

  ANGLE_CONVERTER_FIRST = /<(?:(?:[^:<>]+):)?([A-Za-z_][A-Za-z0-9_]*)>/
  ANGLE_BODY            = /<([^>]+)>/
  SEGMENT_COLON_IDENT   = /(?<=\A|\/):([A-Za-z_]\w*)/
  DOLLAR_SLOTS          = {DOLLAR_BRACED_IDENT, DOLLAR_IDENT}
  COLON_THEN_BRACE      = {COLON_WORD, BRACE_WORD}

  # Callers that need the rewritten path and its declared names take both
  # from the same matches. A framework can supply names for anonymous slots.
  def self.rewrite_names(path : String, pattern : Regex, *, colon : Bool = false, &)
    names = [] of String
    rewritten = path.gsub(pattern) do |_, match|
      name = yield match
      names << name
      colon ? ":#{name}" : "{#{name}}"
    end
    {rewritten, names}
  end

  def self.rewrite_names(path : String, pattern : Regex)
    rewrite_names(path, pattern) { |match| match[1] }
  end

  BRACE_BODY         = /\{([^}]+)\}/
  BRACE_SEGMENT_BODY = /\{([^}\/]+)\}/
  BRACE_TYPED_WORD   = /\{(\w+):[^}]+\}/
  BRACE_THEN_COLON   = {BRACE_TYPED_WORD, COLON_IDENT}

  # Route templates allow a converter, a default, and an optional or catch-all marker.
  def self.template_name(raw : String) : String
    raw.split(':').first.split('=').first.strip.lstrip('*').rstrip('?')
  end

  def self.template_names(path : String, pattern : Regex = BRACE_BODY, *, trailing_star : Bool = false) : Array(String)
    names(path, pattern).map do |raw|
      name = template_name(raw)
      trailing_star ? name.rstrip('*') : name
    end.uniq!
  end

  def self.bind_optional_slots(path : String, bound : Array(String)) : String
    result = path
    each_name(path, BRACE_BODY) do |raw|
      slot = "{#{raw}}"
      if raw.ends_with?('?') && !bound.includes?(template_name(raw))
        result = result.gsub("/#{slot}", "").gsub("#{slot}/", "").gsub(slot, "")
      elsif raw.ends_with?('?') || raw.includes?('=')
        result = result.gsub(slot, "{#{raw.split('=').first.rstrip('?')}}")
      end
    end
    result
  end

  def self.trimmed_segments(path : String) : Array(String)
    path.split('/').map!(&.strip).reject!(&.empty?)
  end

  def self.brace_interpolation(path : String) : String
    path.gsub(/\#\{([^}]+)\}/) { |_, match| "{#{match[1].strip}}" }
  end

  OPTIONAL_BRACKET_COLON = /\[:(\w+)\]/
  OPTIONAL_THEN_COLON    = { {OPTIONAL_BRACKET_COLON, ":\\1"}, {COLON_WORD, "{\\1}"} }
  SIGIL_SEGMENT          = /(?<=\A|\/)[@?]([^:\/]*)(?::[^\/]*)?/

  # File routers try the catch-all spelling first. Next also accepts double
  # brackets and retains the catch-all marker in the emitted URL.
  def self.bracket_segment(segment : String, *, catch_all : Bool = false) : String
    rest = catch_all ? /^\[\[?\.\.\.(\w+)\]\]?$/ : /^\[\.\.\.(\w+)\]$/
    if match = segment.match(rest)
      return catch_all ? "{*#{match[1]}}" : "{#{match[1]}}"
    end
    match = segment.match(/^\[(\w+)\]$/)
    match ? "{#{match[1]}}" : segment
  end

  # Each pattern captures the name in group one. Successive passes preserve
  # the declaration order *within* each spelling, including repeated names.
  def self.each_name(path : String, *patterns : Regex, &)
    patterns.each do |pattern|
      path.scan(pattern) { |match| yield match[1] }
    end
  end

  def self.names(path : String, *patterns : Regex) : Array(String)
    result = [] of String
    each_name(path, *patterns) { |name| result << name }
    result
  end

  # Apply substitutions in order. Rooting, interior slashes, and removing
  # one trailing slash are independent choices. Empty input can mean an
  # absent prefix (empty: "") or a root route (the default).
  def self.normalize(path : String, *patterns : Regex, rooted : Bool = true,
                     collapse : Bool = false, trim : Bool = false, replacement : String = "{\\1}") : String
    patterns.each { |pattern| path = path.gsub(pattern, replacement) }
    normalize(path, rooted: rooted, collapse: collapse, trim: trim)
  end

  # A replacement may feed the next rule: "[:id]suffix" first becomes
  # ":idsuffix", which is then one colon parameter.
  def self.normalize(path : String, *rules : Tuple(Regex, String), **options) : String
    rules.each { |pattern, replacement| path = path.gsub(pattern, replacement) }
    normalize(path, **options)
  end

  def self.normalize(path : String, *, rooted : Bool = true, collapse : Bool = false,
                     trim : Bool = false, empty : String? = nil) : String
    return empty if path.empty? && empty
    path = "/#{path}" if rooted && !path.starts_with?('/')
    path = path.squeeze('/') if collapse
    path = path.rchop('/') if trim && path.size > 1
    path
  end

  # These templates drop one leading slash on each line, then force a new
  # leading slash. A multi-slash prefix on a nonempty route survives as "//".
  def self.normalize_prefixed_template(route : String) : String
    path = "/" + normalize(route.strip.gsub(/^\//, ""), rooted: false, collapse: true)
    path == "//" ? "/" : path
  end

  def self.before_query_or_fragment(path : String) : String
    path.partition('?')[0].partition('#')[0]
  end

  def self.request_path(path : String) : String
    normalize(before_query_or_fragment(path), collapse: true, trim: true)
  end

  def self.unescape_braces(path : String) : String
    path.gsub("{{", "{").gsub("}}", "}")
  end

  # The path converter spans slashes. The optimizer needs its spelling to
  # distinguish this route from a one-segment parameter.
  def self.strip_type_converters(path : String) : String
    path.gsub(BRACE_TYPED) { |slot, match| slot.ends_with?(":path}") ? slot : "{#{match[1]}}" }
  end

  enum JoinRule
    Collapsed
    TrimSeam
    RequireSeam
    RootChild
    ChompPrefix
    RootedMount
    PreserveRootPrefix
  end

  def self.join(prefix : String, child : String, rule : JoinRule) : String
    case rule
    in .collapsed?
      normalize(join(prefix, child), collapse: true)
    in .require_seam?
      return normalize(child) if prefix.empty?
      return prefix.ends_with?('/') ? prefix : "#{prefix}/" if child.empty?
      join(prefix, child)
    in .trim_seam?
      return child if prefix.empty?
      return prefix if child.empty?
      join_absorbing(prefix, child)
    in .root_child?
      prefix.rchop('/') + normalize(child)
    in .chomp_prefix?
      prefix.empty? ? child : join(prefix, child, :root_child)
    in .preserve_root_prefix?
      return child if prefix.empty?
      return prefix if child.empty?
      base = prefix.size > 1 ? prefix.rchop('/') : prefix
      base + normalize(child)
    in .rooted_mount?
      base = normalize(prefix).rstrip('/')
      return normalize(child) if base.empty?
      tail = child.lstrip('/')
      tail.empty? ? base : "#{base}/#{tail}"
    end
  end
end
