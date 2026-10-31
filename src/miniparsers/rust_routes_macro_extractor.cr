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
  record Entry, path : String, verb : String?, handler : String?, sub : String?, line : Int32
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

  MACRO_RE   = /macro_rules!\s+(\w+)/
  RECORD_KEY = /\A\s*(\w+)\s*:(?!:)\s*(.*?)\s*\z/m
  REC_RULES  = Noir::TopLevelSplit::Rules.new(nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket | Noir::TopLevelSplit::Nest::Brace | Noir::TopLevelSplit::Nest::Angle, quotes: "\"")

  # A `$( $route => [get($attr::get), ...] ),*` repetition inside a table
  # declared in a `macro_rules! NAME`: bind each `NAME!({key: value, ..}, ..)`
  # record's keys to the `$key` metavariables and read the filled-in entry.
  # Not a macro expander: only `{key: value}` records of invocations of the
  # enclosing macro, substituted textually.
  private def self.expand_repetition(text : String, source : String, attr_open : Int32, line : Int32, entries : Array(Entry))
    template = text[2...-1]? || return
    name = source[0, attr_open].scan(MACRO_RE).last?.try(&.[1]) || return
    pos = 0
    inv = Regex.new("(?<![\\w])#{Regex.escape(name)}!\\s*\\(")
    while m = inv.match(source, pos)
      open = m.end(0) - 1
      pos = open + 1
      tail = source[open, MAX_INVOCATION]
      close = matching_paren(tail, 0) || next
      Noir::TopLevelSplit.split(tail[1...close], ',', REC_RULES).each do |rec|
        rec = rec.strip
        next unless rec.starts_with?('{') && rec.ends_with?('}')
        vars = {} of String => String
        Noir::TopLevelSplit.split(rec[1...-1], ',', REC_RULES).each do |kv|
          if km = RECORD_KEY.match(kv)
            vars[km[1]] = km[2]
          end
        end
        filled = template.gsub(/\$(\w+)/) { |_, md| vars[md[1]]? || md[0] }
        parse_entry(filled.strip, line, entries)
      end
    end
  end

  private def self.parse_entry(text : String, line : Int32, entries : Array(Entry))
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
        entries << Entry.new(path, verb.upcase, arg, nil, line)
      end
    end
  end

  private def self.strip_comments(text : String) : String
    text.gsub(%r{//[^\n]*}, "")
  end

  # Index of the `)` closing the `(` at `open`; skips string literals and
  # `//` comments.
  private def self.matching_paren(text : String, open : Int32) : Int32?
    depth = 0
    in_str = false
    i = open
    size = text.size
    while i < size
      c = text[i]
      if in_str
        i += 1 if c == '\\'
        in_str = false if c == '"'
      elsif c == '"'
        in_str = true
      elsif c == '/' && i + 1 < size && text[i + 1] == '/'
        while i < size && text[i] != '\n'
          i += 1
        end
      elsif c == '('
        depth += 1
      elsif c == ')'
        depth -= 1
        return i if depth == 0
      end
      i += 1
    end
    nil
  end
end
