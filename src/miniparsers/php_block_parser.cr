require "../minilexers/php_lexer"

module Noir
  # The block structure of PHP source, read off a `PhpLexer`'s masked text
  # (strings, comments, heredocs and inline HTML blanked), so no delimiter or
  # keyword inside a literal or a comment can open, close or fake a block.
  #
  # One linear pass builds a tree of the constructs analyzers ask about:
  #
  #   * statements: `if` / `elseif` / `else` chains, `try` / `catch` /
  #     `finally`, `switch` and its `case`s, loops, bare `{ }` blocks, with
  #     each construct's parenthesised head (condition, subject) as a span;
  #   * code units: named functions, methods, closures (`function () use
  #     () { }`) and arrow functions (`fn () => expr`), with their parameter
  #     lists, and `match` expressions — also when they sit inside an
  #     argument list or another construct's condition;
  #   * declarations: `class` / `trait` / `interface` / `enum` (and `new
  #     class`) with their methods and properties as members;
  #   * PHP 8 attributes `#[A(...), B]`, attached to the declaration they
  #     precede.
  #
  # Every delimiter pair is matched once up front, so the tree, `close_of`
  # and `array_entries` all answer without rescanning. Ranges are character
  # offsets into the lexed source (same as `PhpLexer#masked`); a block's
  # `body` excludes its braces.
  class PhpBlockParser
    enum Kind
      Root
      Block
      If
      Elseif
      Else
      Try
      Catch
      Finally
      Switch
      Case
      Match
      Foreach
      For
      While
      Do
      Function
      Closure
      ArrowFn
      Class
      Method
      Property
    end

    # One entry of an attribute group: `name` as written (`Route`,
    # `\Symfony\...\Route`), the entry's span, and the span inside its
    # parentheses when it has an argument list.
    record Attribute, name : String, start : Int32, stop : Int32, args : Range(Int32, Int32)?

    # One element of an array literal: the key expression (nil for a list
    # element) and the value expression, both trimmed.
    record ArrayEntry, key : Range(Int32, Int32)?, value : Range(Int32, Int32)

    class Node
      getter kind : Kind
      getter start : Int32
      getter parent : Node?
      getter children = [] of Node
      # End of the whole construct (exclusive).
      property stop : Int32 = 0
      # Inside the parentheses: condition, loop header, `match`/`switch`
      # subject, `catch` types, `case` label, or a code unit's parameters.
      property head : Range(Int32, Int32)? = nil
      # Inside the braces; for a brace-less body, the single statement (or an
      # arrow function's expression).
      property body : Range(Int32, Int32) = 0...0
      property? braced = false
      # Function/method/class name.
      property name : String? = nil
      # The previous link of a chain: the branch before an `elseif`/`else`,
      # the `try` of a `catch`/`finally`.
      property prev : Node? = nil
      # A closure's `use (...)` list.
      property uses : Range(Int32, Int32)? = nil
      property modifiers = [] of String
      property attributes = [] of Attribute

      def initialize(@kind : Kind, @start : Int32, @parent : Node?)
        @parent.try(&.children.<<(self))
      end

      # A function, method, closure or arrow function: its own scope.
      def code_unit? : Bool
        kind.function? || kind.method? || kind.closure? || kind.arrow_fn?
      end
    end

    MODIFIERS  = Set{"public", "protected", "private", "static", "final", "abstract", "readonly", "var"}
    CLASS_KIND = Set{"class", "trait", "interface", "enum"}

    getter root : Node
    getter lexer : PhpLexer
    # Every attribute in source order.
    getter attributes = [] of Attribute

    @m : Array(Char)
    @size : Int32
    @close : Array(Int32)
    @pending = [] of Attribute

    def initialize(@lexer : PhpLexer)
      @m = @lexer.masked
      @size = @m.size
      @close = pair_delimiters
      @root = Node.new(Kind::Root, 0, nil)
      @root.body = 0...@size
      parse_statements(0, @size, @root)
      @root.stop = @size
    end

    def self.new(source : String, *, php_mode : Bool = false)
      new(PhpLexer.new(source, php_mode: php_mode))
    end

    # The delimiter closing the `(` / `[` / `{` at `open`, or nil.
    def close_of(open : Int32) : Int32?
      c = @close[open]? || -1
      c >= 0 ? c : nil
    end

    # The nodes enclosing `pos`, outermost first (the root excluded).
    def path(pos : Int32) : Array(Node)
      out = [] of Node
      node = @root
      while child = child_at(node, pos)
        out << child
        node = child
      end
      out
    end

    # Depth-first, in source order.
    def each_node(& : Node ->) : Nil
      stack = @root.children.reverse
      while node = stack.pop?
        yield node
        node.children.reverse_each { |child| stack << child }
      end
    end

    # `class` / `trait` / `interface` / `enum` declarations outside any
    # function: at the top level, in a `namespace { }` block, or declared
    # under a condition (`if (! class_exists(X::class)) { class X ... }`).
    def declarations : Array(Node)
      found = [] of Node
      stack = @root.children.reverse
      while node = stack.pop?
        if node.kind.class?
          found << node
        elsif !node.code_unit?
          node.children.reverse_each { |child| stack << child }
        end
      end
      found
    end

    # Elements of the array literal whose `[` (or `array(`'s `(`) is at
    # `open`, or nil when it does not close.
    def array_entries(open : Int32) : Array(ArrayEntry)?
      return unless close = close_of(open)
      entries = [] of ArrayEntry
      pos = open + 1
      while (start = skip_blank(pos, close)) < close
        stop = start
        arrow = nil
        while stop < close
          c = @m[stop]
          if c == '(' || c == '[' || c == '{'
            stop = (close_of(stop) || close - 1) + 1
            next
          end
          break if c == ','
          if c == '=' && @m[stop + 1]? == '>' && arrow.nil?
            arrow = stop
            stop += 2
            next
          end
          stop += 1
        end
        if arrow && !arrow_fn_at?(start)
          entries << ArrayEntry.new(start...trim_blank(start, arrow), skip_blank(arrow + 2, stop)...trim_blank(start, stop))
        else
          entries << ArrayEntry.new(nil, start...trim_blank(start, stop))
        end
        pos = stop + 1
      end
      entries
    end

    # ---- pass ---------------------------------------------------------------

    private def pair_delimiters : Array(Int32)
      close = Array(Int32).new(@size, -1)
      parens = [] of Int32
      brackets = [] of Int32
      braces = [] of Int32
      @m.each_with_index do |c, i|
        case c
        when '(' then parens << i
        when '[' then brackets << i
        when '{' then braces << i
        when ')' then parens.pop?.try { |o| close[o] = i }
        when ']' then brackets.pop?.try { |o| close[o] = i }
        when '}' then braces.pop?.try { |o| close[o] = i }
        end
      end
      close
    end

    private def child_at(node : Node, pos : Int32) : Node?
      kids = node.children
      idx = kids.bsearch_index { |kid| kid.stop > pos }
      idx && kids[idx].start <= pos ? kids[idx] : nil
    end

    private def parse_statements(from : Int32, to : Int32, parent : Node) : Nil
      pos = from
      while (pos = skip_ws(pos, to)) < to
        attribute = attribute_at?(pos)
        pos = Math.max(parse_statement(pos, to, parent), pos + 1)
        @pending.clear unless attribute
      end
    end

    # Index just past the statement at `pos`.
    private def parse_statement(pos : Int32, to : Int32, parent : Node) : Int32
      c = @m[pos]
      return parse_braced(Node.new(Kind::Block, pos, parent), pos, to) if c == '{'
      return pos + 1 if c == ';' || c == '}' || c == ')' || c == ']'
      return parse_attribute_group(pos, to) if attribute_at?(pos)
      return parse_expression(pos, to, parent, :statement) unless ident_start?(c)

      word = read_word(pos) || ""
      case word
      when "if"     then parse_if(pos, pos + 2, to, parent, Kind::If)
      when "elseif" then parse_if(pos, pos + 6, to, parent, Kind::Elseif)
      when "else"
        after = skip_ws(pos + 4, to)
        if kw?(after, "if")
          parse_if(pos, after + 2, to, parent, Kind::Elseif)
        else
          node = Node.new(Kind::Else, pos, parent)
          node.stop = parse_body(pos + 4, to, node)
        end
      when "while"   then parse_headed(Node.new(Kind::While, pos, parent), pos + 5, to).stop
      when "for"     then parse_headed(Node.new(Kind::For, pos, parent), pos + 3, to).stop
      when "foreach" then parse_headed(Node.new(Kind::Foreach, pos, parent), pos + 7, to).stop
      when "switch"  then parse_switch(pos, to, parent)
      when "try"     then parse_try(pos, to, parent)
      when "do"      then parse_do(pos, to, parent)
      when "namespace"
        # `namespace App\X { ... }` (or a global `namespace { ... }`) holds
        # its declarations in a block.
        p = skip_ws(pos + 9, to)
        while p < to && (ident_char?(@m[p]) || @m[p] == '\\')
          p += 1
        end
        p = skip_ws(p, to)
        if @m[p]? == '{'
          parse_braced(Node.new(Kind::Block, p, parent), p, to)
        else
          parse_expression(pos, to, parent, :statement)
        end
      when "function"
        after = skip_ws(pos + 8, to)
        after = skip_ws(after + 1, to) if @m[after]? == '&'
        if after < to && ident_start?(@m[after])
          parse_function(Node.new(Kind::Function, pos, parent), after, to)
        else
          parse_expression(pos, to, parent, :statement)
        end
      else
        if MODIFIERS.includes?(word) || CLASS_KIND.includes?(word)
          if stop = parse_class(pos, to, parent)
            return stop
          end
        end
        parse_expression(pos, to, parent, :statement)
      end
    end

    private def parse_if(start : Int32, after_kw : Int32, to : Int32, parent : Node, kind : Kind) : Int32
      alt = alt_body_at?(after_kw, to, headed: true)
      node = parse_headed(Node.new(kind, start, parent), after_kw, to)
      loop do
        q = skip_ws(node.stop, to)
        r = skip_ws(q + 4, to)
        # A branch continues the chain only in the chain's own syntax: after a
        # braced `if` nested in an `if (): ... endif;` body, the `elseif ():`
        # that follows is the outer one's.
        if kw?(q, "elseif") && alt_body_at?(q + 6, to, headed: true) == alt
          link = parse_headed(Node.new(Kind::Elseif, q, parent), q + 6, to)
        elsif kw?(q, "else") && kw?(r, "if") && alt_body_at?(r + 2, to, headed: true) == alt
          link = parse_headed(Node.new(Kind::Elseif, q, parent), r + 2, to)
        elsif kw?(q, "else") && !kw?(r, "if") && alt_body_at?(q + 4, to, headed: false) == alt
          link = Node.new(Kind::Else, q, parent)
          link.stop = parse_body(q + 4, to, link)
        else
          return node.stop
        end
        link.prev = node
        node = link
      end
    end

    # Whether the branch whose keyword ends at `after_kw` (and has a `(...)`
    # head when `headed`) opens an alternative-syntax `:` body.
    private def alt_body_at?(after_kw : Int32, to : Int32, headed : Bool) : Bool
      p = skip_ws(after_kw, to)
      if headed
        return false unless @m[p]? == '(' && (close = close_of(p))
        p = skip_ws(close + 1, to)
      end
      @m[p]? == ':'
    end

    # `kw (head) body`: the head's span, then the body.
    private def parse_headed(node : Node, after_kw : Int32, to : Int32) : Node
      p = parse_head(node, after_kw, to)
      node.stop = parse_body(p, to, node)
      node
    end

    private def parse_head(node : Node, after_kw : Int32, to : Int32) : Int32
      p = skip_ws(after_kw, to)
      return p unless @m[p]? == '(' && (close = close_of(p)) && close < to
      node.head = (p + 1)...close
      parse_expression(p + 1, close, node, :region)
      close + 1
    end

    private def parse_body(p : Int32, to : Int32, node : Node) : Int32
      p = skip_ws(p, to)
      return p if p >= to
      return parse_braced(node, p, to) if @m[p] == '{'
      return parse_alt_body(p, to, node) if @m[p] == ':' && ALT_STOPS.has_key?(node.kind)
      p = skip_ws(p + 1, to) if @m[p] == ':'
      return p if p >= to
      stop = parse_statement(p, to, node)
      node.body = p...stop
      stop
    end

    # The words that end an alternative-syntax body (`if (x): ... endif;`).
    ALT_STOPS = {
      Kind::If      => {"elseif", "else", "endif"},
      Kind::Elseif  => {"elseif", "else", "endif"},
      Kind::Else    => {"endif"},
      Kind::Foreach => {"endforeach"},
      Kind::For     => {"endfor"},
      Kind::While   => {"endwhile"},
      Kind::Switch  => {"endswitch"},
    }

    # `: statements end<kw>;` — the statements up to the word that ends this
    # branch. An `end<kw>` (and its `;`) is consumed; an `else:` / `elseif`
    # is left for the chain.
    private def parse_alt_body(colon : Int32, to : Int32, node : Node) : Int32
      stops = ALT_STOPS[node.kind]
      start = skip_ws(colon + 1, to)
      pos = start
      word = nil
      while (q = skip_ws(pos, to)) < to
        word = read_word(q)
        break if word && stops.includes?(word) && keyword_boundary?(q)
        word = nil
        pos = Math.max(parse_statement(q, to, node), q + 1)
      end
      node.body = start...pos
      q = skip_ws(pos, to)
      return q unless word && word.starts_with?("end")
      q = skip_ws(q + word.size, to)
      @m[q]? == ';' ? q + 1 : q
    end

    private def parse_braced(node : Node, open : Int32, to : Int32, members : Bool = false) : Int32
      close = close_of(open)
      close = to if close.nil? || close >= to
      node.braced = true
      node.body = (open + 1)...close
      if members
        parse_members(open + 1, close, node)
      elsif node.kind.switch?
        parse_cases(open + 1, close, node)
      elsif node.kind.match?
        parse_expression(open + 1, close, node, :region)
      else
        parse_statements(open + 1, close, node)
      end
      node.stop = Math.min(close + 1, to)
    end

    private def parse_switch(pos : Int32, to : Int32, parent : Node) : Int32
      node = Node.new(Kind::Switch, pos, parent)
      p = skip_ws(parse_head(node, pos + 6, to), to)
      node.stop = @m[p]? == '{' ? parse_braced(node, p, to) : parse_body(p, to, node)
    end

    # `case x:` / `default:` labels; the statements after one are its children.
    private def parse_cases(from : Int32, to : Int32, switch : Node) : Nil
      current = nil
      pos = from
      while (pos = skip_ws(pos, to)) < to
        label = kw?(pos, "case") ? 4 : (kw?(pos, "default") ? 7 : 0)
        if label > 0
          colon = label_end(pos + label, to)
          current = Node.new(Kind::Case, pos, switch)
          current.head = (pos + label)...colon
          pos = Math.min(colon + 1, to)
          current.body = pos...pos
          current.stop = pos
        else
          pos = Math.max(parse_statement(pos, to, current || switch), pos + 1)
          if node = current
            node.body = node.body.begin...pos
            node.stop = pos
          end
        end
      end
    end

    private def label_end(p : Int32, to : Int32) : Int32
      while p < to
        c = @m[p]
        if c == '(' || c == '[' || c == '{'
          p = (close_of(p) || to - 1) + 1
          next
        end
        if c == ':'
          return p unless @m[p + 1]? == ':'
          p += 2
          next
        end
        return p if c == ';'
        p += 1
      end
      to
    end

    private def parse_try(pos : Int32, to : Int32, parent : Node) : Int32
      guarded = Node.new(Kind::Try, pos, parent)
      p = guarded.stop = parse_body(pos + 3, to, guarded)
      loop do
        q = skip_ws(p, to)
        if kw?(q, "catch")
          link = parse_headed(Node.new(Kind::Catch, q, parent), q + 5, to)
        elsif kw?(q, "finally")
          link = Node.new(Kind::Finally, q, parent)
          link.stop = parse_body(q + 7, to, link)
        else
          return p
        end
        link.prev = guarded
        p = link.stop
      end
    end

    private def parse_do(pos : Int32, to : Int32, parent : Node) : Int32
      node = Node.new(Kind::Do, pos, parent)
      p = parse_body(pos + 2, to, node)
      q = skip_ws(p, to)
      if kw?(q, "while")
        p = parse_head(node, q + 5, to)
        q = skip_ws(p, to)
        p = q + 1 if @m[q]? == ';'
      end
      node.stop = p
    end

    # A named function or method: `name (params) [: type] { body }` or `;`.
    private def parse_function(node : Node, name_at : Int32, to : Int32) : Int32
      name_end = word_end(name_at)
      node.name = @m[name_at...name_end].join
      node.attributes = take_pending
      p = parse_head(node, name_end, to)
      while p < to && @m[p] != '{' && @m[p] != ';'
        p += 1
      end
      return node.stop = Math.min(p + 1, to) if p >= to || @m[p] == ';'
      parse_braced(node, p, to)
    end

    # `[modifiers] class|trait|interface|enum Name ... { members }`, or nil
    # when the words at `pos` are not a declaration.
    private def parse_class(pos : Int32, to : Int32, parent : Node) : Int32?
      mods = [] of String
      p = pos
      while (word = read_word(p)) && MODIFIERS.includes?(word)
        mods << word
        p = skip_ws(p + word.size, to)
      end
      return unless (word = read_word(p)) && CLASS_KIND.includes?(word)
      name_at = skip_ws(p + word.size, to)
      return unless name_at < to && ident_start?(@m[name_at])
      return if word == "enum" && !(@m[skip_ws(word_end(name_at), to)]?.try { |c| c == '{' || c == ':' || c == 'i' })
      node = Node.new(Kind::Class, pos, parent)
      node.name = @m[name_at...word_end(name_at)].join
      node.modifiers = mods
      node.attributes = take_pending
      class_body(node, word_end(name_at), to)
    end

    private def class_body(node : Node, p : Int32, to : Int32) : Int32
      while p < to && @m[p] != '{' && @m[p] != ';'
        if @m[p] == '('
          close = close_of(p) || to - 1
          parse_expression(p + 1, close, node, :region)
          p = close
        end
        p += 1
      end
      return node.stop = Math.min(p + 1, to) if p >= to || @m[p] == ';'
      parse_braced(node, p, to, members: true)
    end

    private def parse_members(from : Int32, to : Int32, klass : Node) : Nil
      pos = from
      while (pos = skip_ws(pos, to)) < to
        if attribute_at?(pos)
          pos = parse_attribute_group(pos, to)
          next
        end
        if !ident_start?(@m[pos])
          pos = statement_stop(pos, to)
          @pending.clear
          next
        end
        start = pos
        mods = [] of String
        while (word = read_word(pos)) && MODIFIERS.includes?(word)
          mods << word
          pos = skip_ws(pos + word.size, to)
        end
        word = read_word(pos)
        if word == "function"
          name_at = skip_ws(pos + 8, to)
          name_at = skip_ws(name_at + 1, to) if @m[name_at]? == '&'
          if name_at < to && ident_start?(@m[name_at])
            node = Node.new(Kind::Method, start, klass)
            node.modifiers = mods
            pos = parse_function(node, name_at, to)
            next
          end
        elsif word == "use" || word == "const" || word == "case" || mods.empty?
          pos = statement_stop(pos, to)
          @pending.clear
          next
        end
        # A property, possibly typed, possibly a list (`public $a, $b;`), or
        # one with PHP 8.4 hooks (`{ get => ...; }`).
        node = Node.new(Kind::Property, start, klass)
        node.modifiers = mods
        node.attributes = take_pending
        p = pos
        while p < to && @m[p] != ';' && @m[p] != '{'
          p = @m[p] == '(' || @m[p] == '[' ? (close_of(p) || to - 1) + 1 : p + 1
        end
        p = (close_of(p) || to - 1) if p < to && @m[p] == '{'
        node.body = pos...Math.min(p, to)
        pos = node.stop = Math.min(p + 1, to)
      end
    end

    # Index just past the `;` ending the statement at `p` (brackets skipped
    # whole), or `to`.
    private def statement_stop(p : Int32, to : Int32) : Int32
      while p < to
        c = @m[p]
        if c == '(' || c == '[' || c == '{'
          p = (close_of(p) || to - 1) + 1
          next
        end
        return p + 1 if c == ';'
        p += 1
      end
      to
    end

    # Scan an expression for the code units nested in it. `:statement` stops
    # after the `;` ending it, `:arrow` (an arrow function's body) at the
    # first top-level `,` or `;`, both at a closer that would pop above the
    # start; `:region` runs to `to`. Returns where it stopped.
    private def parse_expression(pos : Int32, to : Int32, parent : Node, mode : Symbol) : Int32
      depth = 0
      i = pos
      while i < to
        c = @m[i]
        case c
        when '(', '[', '{'
          if c == '[' && i > 0 && @m[i - 1] == '#'
            i = parse_attribute_group(i - 1, to, pending: false)
            next
          end
          depth += 1
        when ')', ']', '}'
          return i if depth == 0 && mode != :region
          depth -= 1 if depth > 0
        when ';'
          return (mode == :statement ? i + 1 : i) if depth == 0 && mode != :region
        when ','
          return i if depth == 0 && mode == :arrow
        when '$'
          i = word_end(i + 1)
          next
        else
          if ident_start?(c)
            stop = word_end(i)
            if keyword_boundary?(i)
              case stop - i
              when 8
                i = parse_closure(i, to, parent) if kw?(i, "function")
              when 2
                i = parse_arrow(i, to, parent) if kw?(i, "fn")
              when 5
                i = parse_match(i, to, parent) if kw?(i, "match")
              when 3
                q = skip_ws(stop, to)
                if kw?(i, "new") && kw?(q, "class")
                  node = Node.new(Kind::Class, i, parent)
                  node.attributes = take_pending
                  i = class_body(node, q + 5, to)
                end
              end
            end
            i = Math.max(i, stop)
            next
          end
        end
        i += 1
      end
      i
    end

    private def parse_closure(pos : Int32, to : Int32, parent : Node) : Int32
      p = skip_ws(pos + 8, to)
      p = skip_ws(p + 1, to) if @m[p]? == '&'
      return pos + 8 unless @m[p]? == '(' && (close = close_of(p)) && close < to
      node = Node.new(Kind::Closure, pos, parent)
      node.attributes = take_pending
      node.head = (p + 1)...close
      parse_expression(p + 1, close, node, :region)
      p = skip_ws(close + 1, to)
      if kw?(p, "use") && @m[q = skip_ws(p + 3, to)]? == '(' && (use_close = close_of(q))
        node.uses = (q + 1)...use_close
        p = use_close + 1
      end
      while p < to && @m[p] != '{' && @m[p] != ';'
        p += 1
      end
      return node.stop = p if p >= to || @m[p] == ';'
      parse_braced(node, p, to)
    end

    private def parse_arrow(pos : Int32, to : Int32, parent : Node) : Int32
      p = skip_ws(pos + 2, to)
      p = skip_ws(p + 1, to) if @m[p]? == '&'
      return pos + 2 unless @m[p]? == '(' && (close = close_of(p)) && close < to
      node = Node.new(Kind::ArrowFn, pos, parent)
      node.attributes = take_pending
      node.head = (p + 1)...close
      parse_expression(p + 1, close, node, :region)
      p = close + 1
      while p < to && !(@m[p] == '=' && @m[p + 1]? == '>')
        p += 1
      end
      start = skip_ws(p + 2, to)
      stop = start < to ? parse_expression(start, to, node, :arrow) : start
      node.body = start...stop
      node.stop = Math.max(stop, pos + 2)
    end

    private def parse_match(pos : Int32, to : Int32, parent : Node) : Int32
      p = skip_ws(pos + 5, to)
      return pos + 5 unless @m[p]? == '('
      node = Node.new(Kind::Match, pos, parent)
      p = skip_ws(parse_head(node, pos + 5, to), to)
      return node.stop = p unless @m[p]? == '{'
      parse_braced(node, p, to)
    end

    # `#[A(...), B]` at `pos`: recorded, kept for the next declaration.
    # A group inside an expression (a parameter's `#[CurrentUser]`) is
    # recorded but not kept for the next declaration.
    private def parse_attribute_group(pos : Int32, to : Int32, pending : Bool = true) : Int32
      close = close_of(pos + 1) || to - 1
      p = pos + 2
      while (start = skip_ws(p, close)) < close
        name_end = start
        while name_end < close && (ident_char?(@m[name_end]) || @m[name_end] == '\\')
          name_end += 1
        end
        stop = name_end
        args = nil
        q = skip_ws(name_end, close)
        if @m[q]? == '(' && (args_close = close_of(q)) && args_close < close
          args = (q + 1)...args_close
          stop = args_close + 1
        end
        while stop < close && @m[stop] != ','
          stop += 1
        end
        attribute = Attribute.new(@m[start...name_end].join, start, stop, args)
        @attributes << attribute
        @pending << attribute if pending
        p = stop + 1
      end
      Math.min(close + 1, to)
    end

    private def take_pending : Array(Attribute)
      return [] of Attribute if @pending.empty?
      taken = @pending.dup
      @pending.clear
      taken
    end

    # ---- characters ---------------------------------------------------------

    private def attribute_at?(pos : Int32) : Bool
      @m[pos] == '#' && @m[pos + 1]? == '['
    end

    # `fn (` / `static fn (` / `function (`: a code unit, not a key.
    private def arrow_fn_at?(pos : Int32) : Bool
      pos = skip_ws(word_end(pos), @size) if kw?(pos, "static")
      kw?(pos, "fn") || kw?(pos, "function")
    end

    private def skip_ws(pos : Int32, to : Int32) : Int32
      while pos < to && @m[pos].whitespace?
        pos += 1
      end
      pos
    end

    # Whitespace and comments, not a string literal (also blank in `@m`).
    private def blank?(pos : Int32) : Bool
      @m[pos].whitespace? && !@lexer.literal?(pos)
    end

    private def skip_blank(pos : Int32, to : Int32) : Int32
      while pos < to && blank?(pos)
        pos += 1
      end
      pos
    end

    private def trim_blank(start : Int32, stop : Int32) : Int32
      while stop > start && blank?(stop - 1)
        stop -= 1
      end
      stop
    end

    private def word_end(pos : Int32) : Int32
      while pos < @size && ident_char?(@m[pos])
        pos += 1
      end
      pos
    end

    # The lower-cased word at `pos` (nil unless an identifier starts there).
    private def read_word(pos : Int32) : String?
      return unless pos < @size && ident_start?(@m[pos])
      String.build { |io| (pos...word_end(pos)).each { |i| io << @m[i].downcase } }
    end

    # Whether the whole word `word` (lower-case) sits at `pos` as a keyword.
    private def kw?(pos : Int32, word : String) : Bool
      return false unless pos + word.size <= @size
      word.each_char_with_index { |ch, k| return false unless @m[pos + k].downcase == ch }
      return false if pos + word.size < @size && ident_char?(@m[pos + word.size])
      keyword_boundary?(pos)
    end

    # Not a member/variable/namespaced name: `->fn`, `::match`, `$fn`, `\if`.
    private def keyword_boundary?(pos : Int32) : Bool
      return true if pos == 0
      prev = @m[pos - 1]
      return false if ident_char?(prev) || prev == '$' || prev == '\\'
      return false if prev == '>' && pos >= 2 && @m[pos - 2] == '-'
      return false if prev == ':' && pos >= 2 && @m[pos - 2] == ':'
      true
    end

    private def ident_char?(c : Char) : Bool
      c == '_' || c.ascii_alphanumeric? || c.ord >= 0x80
    end

    private def ident_start?(c : Char) : Bool
      c == '_' || c.ascii_letter? || c.ord >= 0x80
    end
  end
end
