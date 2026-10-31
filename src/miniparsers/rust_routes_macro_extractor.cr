require "../utils/top_level_split"

# Route tables declared through a project-local `#[routes::routes(...)]`
# attribute (Meilisearch's actix-web DSL):
#
#   #[routes::routes(routes(
#       "" => [get(list), post(create)],
#       "/{uid}/documents" => sub(documents::DocumentsApi),
#   ))]
#   pub struct IndexesApi;
#
# A `"path" => verb(handler)` entry is a route; `"path" => sub(Type)` mounts
# the table declared on `Type` under `path`. No file I/O: `extract` takes
# source text, the analyzer resolves `sub` across files.
module Noir::RustRoutesMacro
  # `generated`: the handler is `mod::fn` where `mod` is a module a
  # `macro_rules!` transcriber declares (`pub mod $attr`) for this very record.
  record Entry, path : String, verb : String?, handler : String?, sub : String?, line : Int32, generated : Bool = false
  record Table, owner : String, entries : Array(Entry)

  ATTR_RE        = /#\[\s*(?:\w+::)*routes\s*::\s*routes\s*\(/
  ROUTES_RE      = /(?<![\w])routes\s*\(/
  OWNER_RE       = /\G\s*\]\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?struct\s+(\w+)/
  MAX_ATTR       =  20_000
  MAX_INVOCATION = 500_000
  VERBS          = %w[get post put patch delete head options]
  RULES          = Noir::TopLevelSplit::Rules.new(quotes: "\"")
  ENTRY_RE       = /\A"([^"]*)"\s*=>\s*(.+)\z/m
  CALL_RE        = /\A(\w+)\s*\(\s*([\w:]+)\s*\)\z/
  MACRO_RE       = /macro_rules!\s+(\w+)/
  MOD_VAR_RE     = /\bmod\s+\$(\w+)/
  KEY_VAR_RE     = /(\w+)\s*:\s*\$(\w+)\s*:\s*\w+/

  def self.extract(source : String) : Array(Table)
    tables = [] of Table
    pos = 0
    while m = ATTR_RE.match(source, pos)
      attr_open = m.end(0) - 1
      # ponytail: an attribute longer than MAX_ATTR chars is skipped (bounds
      # the non-ASCII O(n) char indexing of `String#[]`).
      tail = source[attr_open, MAX_ATTR]
      close_rel = matching_paren(tail, 0)
      attr_close = attr_open + (close_rel || 1)
      pos = attr_close
      next unless close_rel
      args = tail[1...close_rel]
      r = ROUTES_RE.match(args) || next
      r_open = (r.end(0) - 1)
      r_close = matching_paren(args, r_open) || next
      owner = OWNER_RE.match(source, attr_close + 1).try(&.[1]) || next
      base_line = source[0, attr_open + 1 + r_open + 1].count('\n') + 1
      body = args[(r_open + 1)...r_close]
      entries = [] of Entry
      Noir::TopLevelSplit.split_spans(body, ',', RULES).each do |part, off|
        line = base_line + body[0, off.clamp(0, body.size)].count('\n')
        text = strip_comments(part).strip
        if text.starts_with?("$(")
          expand_repetition(text, source, attr_open, line, entries)
        else
          parse_entry(text, line, entries)
        end
      end
      tables << Table.new(owner, entries)
    end
    tables
  end

  # What an arm of the enclosing `macro_rules!` accepts: records
  # `{key: $var:frag, ..}` (one, or a `$( {..} SEP )SEP*` repetition).
  private record Shape, keys : Array(String), vars : Array(String), repeat : Bool, inner_sep : Bool, outer_sep : Bool

  # A `$( $route => [get($attr::get), ...] ),*` repetition inside a table
  # declared in a `macro_rules! NAME`: the arm whose transcriber holds the
  # table says which `NAME!({key: value, ..}, ..)` invocations feed it and
  # which `$var` each record key binds; every matching record fills the
  # template. Not a macro expander: only brace records of the enclosing
  # macro's own invocations; an arm shaped otherwise expands nothing.
  # ponytail: matcher fragments are not type-checked and delimiters other
  # than `{}` records are not read.
  private def self.expand_repetition(text : String, source : String, attr_open : Int32, line : Int32, entries : Array(Entry))
    template = text[2...-1]? || return
    m = source[0, attr_open].scan(MACRO_RE).last? || return
    start = m.begin(0)
    macro_text = source[start, MAX_INVOCATION]
    arm = enclosing_arm(macro_text, m[0].size, attr_open - start) || return
    shape = arm_shape(arm) || return
    mod_vars = macro_text.scan(MOD_VAR_RE).map(&.[1])
    pos = 0
    inv = Regex.new("(?<![\\w])#{Regex.escape(m[1])}!\\s*\\(")
    while im = inv.match(source, pos)
      open = im.end(0) - 1
      pos = open + 1
      itail = source[open, MAX_INVOCATION]
      close = matching_paren(itail, 0) || next
      args = itail[1...close]
      next unless shape_accepts?(shape, args, args.rstrip.ends_with?(','))
      Noir::TopLevelSplit.split(args, ',', RULES).each do |rec|
        rec = rec.strip
        next if rec.empty?
        values = parse_record(rec, shape.keys) || next
        vars = {} of String => String
        shape.vars.each_with_index { |var, i| vars[var] = values[i] }
        filled = template.gsub(/\$(\w+)/) { |_, md| vars[md[1]]? || md[0] }
        parse_entry(filled.strip, line, entries, mod_vars.compact_map { |v| vars[v]? }.to_set)
      end
    end
  end

  # The matcher text of the arm of the macro (its text starts at
  # `macro_rules! NAME`; `from` is past the name) whose transcriber contains
  # char offset `at`.
  private def self.enclosing_arm(macro_text : String, from : Int32, at : Int32) : String?
    chars = macro_text.chars
    body_open = (from...chars.size).find { |k| chars[k] == '{' } || return
    body_close = matching_delim(chars, body_open, '{', '}') || return
    i = body_open + 1
    while i < body_close
      while i < body_close && (chars[i].whitespace? || chars[i] == ';')
        i += 1
      end
      break if i >= body_close
      m_open = i
      m_close = matching_delim(chars, m_open, chars[m_open], closer(chars[m_open])) || return
      j = m_close + 1
      while j < body_close && chars[j].whitespace?
        j += 1
      end
      return unless chars[j]? == '=' && chars[j + 1]? == '>'
      j += 2
      while j < body_close && chars[j].whitespace?
        j += 1
      end
      t_close = matching_delim(chars, j, chars[j], closer(chars[j])) || return
      return chars[(m_open + 1)...m_close].join if at > j && at < t_close
      i = t_close + 1
    end
    nil
  end

  private def self.closer(open : Char) : Char
    open == '(' ? ')' : (open == '[' ? ']' : '}')
  end

  private def self.arm_shape(matcher : String) : Shape?
    if rep = matcher.index("$(")
      r_close = matching_paren(matcher, rep + 1) || return
      group = matcher[(rep + 2)...r_close]
      rb_open = group.index('{') || return
      rb_close = matching_delim(group.chars, rb_open, '{', '}') || return
      pairs = group[rb_open..rb_close].scan(KEY_VAR_RE)
      return if pairs.empty?
      outer = matcher[(r_close + 1)..].gsub(/[*+?]/, "").strip
      Shape.new(pairs.map(&.[1]), pairs.map(&.[2]), true, group[(rb_close + 1)..].strip == ",", outer == ",")
    else
      pairs = matcher.scan(KEY_VAR_RE)
      return if pairs.empty?
      Shape.new(pairs.map(&.[1]), pairs.map(&.[2]), false, false, false)
    end
  end

  # Whether an invocation's argument list is one the arm matches: a
  # trailing comma exactly where its separators ask for one.
  private def self.shape_accepts?(shape : Shape, args : String, trailing : Bool) : Bool
    return !trailing && !args.blank? unless shape.repeat
    return true if args.blank?
    shape.inner_sep ? trailing : !trailing
  end

  # `{k1: v1, k2: v2}` read by the arm's key order: a value runs to the
  # depth-0 comma that is followed by the next key, so generics, `->` and
  # `<` in a value need no angle counting. Nil when the keys differ.
  private def self.parse_record(rec : String, keys : Array(String)) : Array(String)?
    return unless rec.starts_with?('{') && rec.ends_with?('}')
    chars = rec[1...-1].chars
    i = 0
    values = [] of String
    keys.each_with_index do |key, ki|
      while i < chars.size && chars[i].whitespace?
        i += 1
      end
      return unless chars[i, key.size]? == key.chars
      i += key.size
      while i < chars.size && chars[i].whitespace?
        i += 1
      end
      return unless chars[i]? == ':'
      i += 1
      from = i
      depth = 0
      quote = false
      stop = nil
      while i < chars.size
        c = chars[i]
        if quote
          i += 1 if c == '\\'
          quote = false if c == '"'
        elsif c == '"'
          quote = true
        elsif c == '(' || c == '[' || c == '{'
          depth += 1
        elsif c == ')' || c == ']' || c == '}'
          depth -= 1
        elsif c == ',' && depth == 0 && (ki == keys.size - 1 || key_follows?(chars, i + 1, keys[ki + 1]))
          stop = i
          break
        end
        i += 1
      end
      return if stop.nil? && ki < keys.size - 1
      values << chars[from...(stop || chars.size)].join.strip
      i = stop ? stop + 1 : chars.size
    end
    while i < chars.size && (chars[i].whitespace? || chars[i] == ',')
      i += 1
    end
    i == chars.size ? values : nil
  end

  private def self.key_follows?(chars : Array(Char), from : Int32, key : String) : Bool
    i = from
    while i < chars.size && chars[i].whitespace?
      i += 1
    end
    return false unless chars[i, key.size]? == key.chars
    i += key.size
    while i < chars.size && chars[i].whitespace?
      i += 1
    end
    chars[i]? == ':' && chars[i + 1]? != ':'
  end

  private def self.parse_entry(text : String, line : Int32, entries : Array(Entry), modules : Set(String) = Set(String).new)
    em = ENTRY_RE.match(text) || return
    path = em[1]
    rhs = em[2].strip
    items = rhs.starts_with?('[') && rhs.ends_with?(']') ? Noir::TopLevelSplit.split(rhs[1...-1], ',', RULES) : [rhs]
    items.each do |item|
      cm = CALL_RE.match(strip_comments(item).strip) || next
      verb = cm[1]
      arg = cm[2]
      next if arg.includes?('$') # macro_rules! fragment, not a real name
      if verb == "sub"
        entries << Entry.new(path, nil, nil, arg, line)
      elsif VERBS.includes?(verb)
        entries << Entry.new(path, verb.upcase, arg, nil, line, arg.includes?("::") && modules.includes?(arg.split("::")[0]))
      end
    end
  end

  private def self.strip_comments(text : String) : String
    text.gsub(%r{//[^\n]*}, "")
  end

  # Index of the `)` closing the `(` at `open`; skips string literals and
  # `//` comments.
  private def self.matching_paren(text : String, open : Int32) : Int32?
    matching_delim(text.chars, open, '(', ')')
  end

  private def self.matching_delim(chars : Array(Char), open : Int32, opener : Char, closer : Char) : Int32?
    depth = 0
    in_str = false
    i = open
    size = chars.size
    while i < size
      c = chars[i]
      if in_str
        i += 1 if c == '\\'
        in_str = false if c == '"'
      elsif c == '"'
        in_str = true
      elsif c == '/' && i + 1 < size && chars[i + 1] == '/'
        while i < size && chars[i] != '\n'
          i += 1
        end
      elsif c == opener
        depth += 1
      elsif c == closer
        depth -= 1
        return i if depth == 0
      end
      i += 1
    end
    nil
  end
end
