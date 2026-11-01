require "../minilexers/csharp_lexer"

module Noir
  # The declarations of one C# source file, read off `CSharpLexer`'s masked
  # view: namespaces (block and file-scoped), types (class / struct /
  # interface / record / enum, partial, generic, with their base list and
  # primary-constructor parameters), and each type's members (methods,
  # constructors with their `: base(...)` arguments, properties, fields),
  # every one with its attributes as structured nodes.
  #
  # Structure is read from the masked chars (strings and comments blanked),
  # so a `]`, `,`, `(` or `{` inside a literal or comment never moves a
  # boundary; every text the nodes carry comes from the comment-blanked code
  # (`CSharpLexer#code_source`), so string literals keep their value.
  #
  # Method bodies are not entered: a body is one span. One linear pass per
  # nesting level, no file access.
  module CSharpDecl
    # One argument of an attribute usage: positional, a constructor
    # parameter by name (`template: "x"`), or a property (`Order = 2`).
    record Arg, text : String, name : String? = nil, property : String? = nil do
      def positional? : Bool
        name.nil? && property.nil?
      end

      # The value of a plain or verbatim string literal; nil for anything
      # else (an interpolation, a constant, a concatenation).
      def literal : String?
        CSharpDecl.literal(text)
      end
    end

    # One attribute of an attribute list. `name` is the simple name without
    # namespace qualification or `Attribute` suffix (`Authorize` for
    # `Microsoft.AspNetCore.Authorization.AuthorizeAttribute`). `target` is
    # the `return:` / `property:` / `assembly:` specifier of its list.
    record Attribute, name : String, qualified : String, args : Array(Arg), target : String?,
      text : String, line : Int32, parens : Bool do
      def positional : Array(Arg)
        args.select(&.positional?)
      end

      # The text between the parentheses, or nil without them.
      def argument_text : String?
        return unless parens
        open = text.index('(') || return
        close = text.rindex(')') || return
        text[open + 1...close]
      end

      # The `Prop = value` argument named `key`.
      def property(key : String) : Arg?
        args.find { |arg| arg.property == key }
      end

      # The constructor argument bound to parameter `key`: by name, else the
      # positional at `index`.
      def argument(key : String, index : Int32 = 0) : Arg?
        args.find { |arg| arg.name == key } || positional[index]?
      end
    end

    record Parameter, attributes : Array(Attribute), modifiers : Array(String), type : String,
      name : String, default : String?, text : String

    # A member of a type. `kind` is :method, :constructor, :operator,
    # :property or :field. `line` is the line of its first non-attribute
    # token, `attr_line` the first line of its attribute lists, `header_end`
    # the line its signature closes on (the parameter list's `)`).
    class Member
      getter kind : Symbol
      getter name : String
      getter modifiers : Array(String)
      getter attributes : Array(Attribute)
      getter return_type : String
      getter type_params : String?
      getter params : Array(Parameter)
      # A constructor's `: base(...)` / `: this(...)` call.
      getter initializer : String?
      getter initializer_args : Array(Arg)?
      getter attr_line : Int32
      getter line : Int32
      getter header_end : Int32
      getter end_line : Int32
      getter header : String
      # Offsets into the source: the body's `{`..`}`, or the `=>` of an
      # expression body (through `finish`).
      getter body_open : Int32?
      getter body_close : Int32?
      getter arrow : Int32?
      getter finish : Int32
      # A property's expression body or initializer, a field's initializer.
      getter value : String?
      # A property's accessor list (`{ get; set; }`).
      getter accessors : String?

      def initialize(@kind, @name, @modifiers, @attributes, @return_type, @type_params, @params,
                     @initializer, @initializer_args, @attr_line, @line, @header_end, @end_line, @header,
                     @body_open, @body_close, @arrow, @finish, @value, @accessors = nil)
      end

      def public? : Bool
        modifiers.includes?("public")
      end

      def static? : Bool
        modifiers.includes?("static")
      end
    end

    class TypeDecl
      getter kind : String
      getter name : String
      getter modifiers : Array(String)
      getter type_params : String?
      getter params : Array(Parameter)?
      getter bases : Array(String)
      getter attributes : Array(Attribute)
      getter namespace : String
      getter outer : TypeDecl?
      getter members = [] of Member
      getter types = [] of TypeDecl
      # Line of the first attribute (or the header when none), of the
      # `class` keyword's declaration, and of the closing brace.
      getter start_line : Int32
      getter line : Int32
      getter end_line : Int32
      getter open : Int32?
      getter close : Int32?
      # The masked text from the first attribute through the body's `{`.
      getter header : String

      def initialize(@kind, @name, @modifiers, @type_params, @params, @bases, @attributes, @namespace,
                     @outer, @start_line, @line, @end_line, @open, @close, @header)
      end

      # The first base-list entry's simple name (`CrudController` for
      # `global::App.CrudController<Item>`).
      def base_name : String?
        bases.first?.try { |base| CSharpDecl.simple_name(base) }
      end

      def methods : Array(Member)
        members.select { |member| member.kind == :method }
      end

      def constructors : Array(Member)
        members.select { |member| member.kind == :constructor }
      end

      def partial? : Bool
        modifiers.includes?("partial")
      end
    end

    class Unit
      getter types : Array(TypeDecl)
      getter top_types : Array(TypeDecl)

      def initialize(@types, @top_types)
        @member_lines = Hash(Int32, Member).new
        types.each do |type|
          type.members.each do |member|
            (member.attr_line..member.header_end).each { |line| @member_lines[line] ||= member }
          end
        end
      end

      # The member whose attributes or signature span `line` (0-based).
      def member_at(line : Int32) : Member?
        @member_lines[line]?
      end

      # The innermost type whose declaration spans `line` (0-based).
      def type_at(line : Int32) : TypeDecl?
        found = nil
        types.each do |type|
          next unless type.start_line <= line && line <= type.end_line
          found = type if found.nil? || type.start_line >= found.start_line
        end
        found
      end
    end

    MODIFIERS = Set{
      "public", "private", "protected", "internal", "static", "abstract", "sealed", "partial",
      "virtual", "override", "readonly", "new", "extern", "unsafe", "async", "volatile", "const",
      "required", "file", "fixed", "ref", "implicit", "explicit",
    }
    PARAM_MODIFIERS = Set{"ref", "out", "in", "params", "this", "scoped", "readonly"}
    TYPE_KEYWORDS   = Set{"class", "struct", "interface", "enum", "record"}

    LITERAL_RE  = /\A"((?:[^"\\\n]|\\.)*)"\z/
    VERBATIM_RE = /\A@"((?:[^"]|"")*)"\z/

    def self.literal(text : String) : String?
      text = text.strip
      if m = text.match(LITERAL_RE)
        m[1].gsub(/\\(.)/) { |_, esc| esc[1] }
      elsif m = text.match(VERBATIM_RE)
        m[1].gsub("\"\"", "\"")
      end
    end

    # `global::A.B.Name<T>(args)` -> `Name`.
    def self.simple_name(text : String) : String
      name = text.strip.lchop("global::")
      cut = name.size
      name.each_char_with_index do |char, i|
        if char == '<' || char == '('
          cut = i
          break
        end
      end
      name[0, cut].split('.').last.strip
    end
  end

  class CSharpDeclParser
    include CSharpDecl

    def self.parse(lexer : CSharpLexer) : CSharpDecl::Unit
      new(lexer).parse
    end

    @m : Array(Char)
    @code : Array(Char)
    @size : Int32
    @line_starts : Array(Int32)

    def initialize(@lexer : CSharpLexer)
      @m = lexer.masked
      @code = lexer.code_source.chars
      @size = @m.size
      @line_starts = [0]
      @m.each_with_index { |char, i| @line_starts << i + 1 if char == '\n' }
      @types = [] of TypeDecl
      @top_types = [] of TypeDecl
    end

    def parse : Unit
      parse_block(0, @size, "", nil)
      Unit.new(@types, @top_types)
    end

    private def line_of(offset : Int32) : Int32
      index = @line_starts.bsearch_index { |start| start > offset } || @line_starts.size
      index - 1
    end

    private def text(from : Int32, to : Int32) : String
      return "" if to <= from
      String.build { |io| (from...Math.min(to, @size)).each { |i| io << @code[i] } }
    end

    private def masked_text(from : Int32, to : Int32) : String
      return "" if to <= from
      String.build { |io| (from...Math.min(to, @size)).each { |i| io << @m[i] } }
    end

    private def skip_ws(i : Int32, stop : Int32 = @size) : Int32
      while i < stop && @m[i].whitespace?
        i += 1
      end
      i
    end

    private def ident_char?(char : Char) : Bool
      char == '_' || char.ascii_alphanumeric? || char.ord >= 0x80
    end

    private def ident_start?(char : Char) : Bool
      char == '_' || char == '@' || char.ascii_letter? || char.ord >= 0x80
    end

    # The identifier at `i` (a leading `@` dropped) and the index after it.
    private def read_ident(i : Int32, stop : Int32) : Tuple(String, Int32)?
      return unless i < stop && ident_start?(@m[i])
      j = @m[i] == '@' ? i + 1 : i
      start = j
      while j < stop && ident_char?(@m[j])
        j += 1
      end
      return if j == start
      {masked_text(start, j), j}
    end

    private def matching(open : Int32, stop : Int32) : Int32?
      close = @lexer.matching_delimiter(open)
      close if close && close < stop
    end

    # Index of the `>` closing the `<` at `open`, or nil.
    private def matching_angle(open : Int32, stop : Int32) : Int32?
      depth = 0
      i = open
      while i < stop
        case @m[i]
        when '<' then depth += 1
        when '>'
          depth -= 1
          return i if depth == 0
        when '{', '}', ';' then return
        end
        i += 1
      end
    end

    private def statement_end(i : Int32, stop : Int32) : Int32
      Math.min(@lexer.statement_end(i), stop)
    end

    # Start of the line holding `i` when only whitespace precedes it there.
    private def line_start?(i : Int32) : Bool
      j = i - 1
      while j >= 0 && @m[j] != '\n'
        return false unless @m[j].whitespace?
        j -= 1
      end
      true
    end

    private def parse_block(from : Int32, stop : Int32, namespace : String, outer : TypeDecl?) : Nil
      i = from
      attrs = [] of Attribute
      attr_start = nil
      while i < stop
        i = skip_ws(i, stop)
        break if i >= stop
        char = @m[i]

        if char == '#' && line_start?(i)
          while i < stop && @m[i] != '\n'
            i += 1
          end
          next
        end

        if char == '['
          close = matching(i, stop) || break
          list = parse_attribute_list(i, close)
          attr_start ||= i
          attrs.concat(list) unless list.any?(&.target.in?("assembly", "module"))
          i = close + 1
          next
        end

        if char == ';' || char == '}' || char == ')' || char == ']'
          i += 1
          attrs = [] of Attribute
          attr_start = nil
          next
        end

        if char == '{'
          i = (matching(i, stop) || stop - 1) + 1
          attrs = [] of Attribute
          attr_start = nil
          next
        end

        header = i
        modifiers = [] of String
        word = nil
        word_at = i
        j = i
        while ident = read_ident(j, stop)
          name, after = ident
          if DECL_MODIFIER.includes?(name) && !(name == "new" && @m[skip_ws(after, stop)]? == '(')
            modifiers << name
            j = skip_ws(after, stop)
          else
            word = name
            word_at = j
            break
          end
        end
        word_at = j if word.nil?

        start = attr_start || header
        if word == "namespace" && outer.nil?
          i = parse_namespace(word_at + 9, stop, namespace)
        elsif word.in?("using", "extern") && outer.nil? && modifiers.empty?
          i = statement_end(word_at, stop)
        elsif word == "delegate"
          i = statement_end(word_at, stop)
        elsif word && TYPE_KEYWORDS.includes?(word) && type_keyword?(word, word_at, stop)
          i = parse_type(start, header, word, word_at, modifiers, attrs, namespace, outer, stop)
        else
          i = parse_member(start, header, modifiers, word_at, attrs, outer, stop)
        end
        attrs = [] of Attribute
        attr_start = nil
      end
    end

    DECL_MODIFIER = CSharpDecl::MODIFIERS

    # `record` is contextual: a type keyword only when a name follows it.
    private def type_keyword?(word : String, at : Int32, stop : Int32) : Bool
      return true unless word == "record"
      after = skip_ws(at + word.size, stop)
      if ident = read_ident(after, stop)
        name, rest = ident
        rest = skip_ws(rest, stop)
        return true if name.in?("class", "struct")
        return @m[rest]?.in?('(', '{', '<', ':') || false
      end
      false
    end

    private def parse_namespace(i : Int32, stop : Int32, namespace : String) : Int32
      j = skip_ws(i, stop)
      start = j
      while j < stop && (ident_char?(@m[j]) || @m[j] == '.')
        j += 1
      end
      name = masked_text(start, j).strip
      full = namespace.empty? ? name : "#{namespace}.#{name}"
      j = skip_ws(j, stop)
      if @m[j]? == ';'
        parse_block(j + 1, stop, full, nil)
        stop
      elsif @m[j]? == '{'
        close = matching(j, stop) || stop
        parse_block(j + 1, close, full, nil)
        close + 1
      else
        j + 1
      end
    end

    private def parse_type(start : Int32, header : Int32, kind : String, at : Int32, modifiers : Array(String),
                           attrs : Array(Attribute), namespace : String, outer : TypeDecl?, stop : Int32) : Int32
      j = skip_ws(at + kind.size, stop)
      if kind == "record" && (ident = read_ident(j, stop)) && ident[0].in?("class", "struct")
        j = skip_ws(ident[1], stop)
      end
      name, j = read_ident(j, stop) || return at + kind.size
      j = skip_ws(j, stop)
      type_params = nil
      if @m[j]? == '<' && (close = matching_angle(j, stop))
        type_params = text(j, close + 1)
        j = skip_ws(close + 1, stop)
      end
      params = nil
      if @m[j]? == '(' && (close = matching(j, stop))
        params = parse_params(j, close)
        j = close + 1
      end
      # The base list and constraints run to the body or the `;`.
      tail = j
      while j < stop && !@m[j].in?('{', ';')
        if @m[j] == '(' && (close = matching(j, stop))
          j = close + 1
        else
          j += 1
        end
      end
      bases = base_list(tail, j)
      open = j < stop && @m[j] == '{' ? j : nil
      close = open.try { |pos| matching(pos, stop) }
      finish = close || (open ? stop : j)
      decl = TypeDecl.new(kind, name, modifiers, type_params, params, bases, attrs, namespace, outer,
        line_of(start), line_of(header), line_of(Math.min(finish, @size - 1)), open, close,
        masked_text(start, (open || j) + 1))
      @types << decl
      if outer
        outer.types << decl
      else
        @top_types << decl
      end
      if (body = open) && kind != "enum"
        parse_block(body + 1, close || stop, namespace, decl)
      end
      Math.min(finish + 1, stop)
    end

    # `: Base<T>, IFoo where T : class` -> ["Base<T>", "IFoo"].
    private def base_list(from : Int32, to : Int32) : Array(String)
      i = skip_ws(from, to)
      return [] of String unless i < to && @m[i] == ':'
      i += 1
      entries = [] of String
      depth = 0
      start = i
      while i < to
        char = @m[i]
        if depth == 0 && char == 'w' && !ident_char?(@m[i - 1]) && masked_text(i, Math.min(i + 6, to)).matches?(/\Awhere\b/)
          break
        end
        case char
        when '<', '(' then depth += 1
        when '>', ')' then depth -= 1 if depth > 0
        when ','
          if depth == 0
            entries << text(start, i).strip
            start = i + 1
          end
        end
        i += 1
      end
      last = text(start, i).strip
      entries << last unless last.empty?
      entries.reject(&.empty?)
    end

    private def parse_member(start : Int32, header : Int32, modifiers : Array(String), from : Int32,
                             attrs : Array(Attribute), outer : TypeDecl?, stop : Int32) : Int32
      i = from
      angle = 0
      while i < stop
        char = @m[i]
        if ident_start?(char) && (ident = read_ident(i, stop))
          word, after = ident
          if word == "operator" && angle == 0
            paren = after
            while paren < stop && @m[paren] != '(' && !@m[paren].in?('{', ';')
              paren += 1
            end
            return finish_callable(start, header, modifiers, from, attrs, outer, stop, paren, :operator, "operator#{masked_text(after, paren).strip}") if @m[paren]? == '('
            return paren + 1
          end
          i = after
          next
        end
        case char
        when '<'
          angle += 1
        when '>'
          angle -= 1 if angle > 0
        when '('
          close = matching(i, stop) || return stop
          if angle == 0 && (callable = callable_name(from, i))
            name, kind = callable
            kind = :constructor if kind == :method && outer && name == outer.name && return_type_text(from, i, name).empty?
            return finish_callable(start, header, modifiers, from, attrs, outer, stop, i, kind, name)
          end
          i = close
        when '['
          i = matching(i, stop) || return stop
        when '{'
          close = matching(i, stop) || return stop
          finish = close + 1
          after = skip_ws(finish, stop)
          value = nil
          if @m[after]? == '=' && @m[after + 1]? != '='
            finish = statement_end(after, stop)
            value = text(after + 1, finish - 1).strip
          end
          record_member(:property, last_word(from, i), modifiers, attrs, outer, start, header, i, finish, value: value, body: {i, close})
          return finish
        when '='
          if @m[i + 1]? == '>'
            finish = statement_end(i, stop)
            record_member(:property, last_word(from, i), modifiers, attrs, outer, start, header, i, finish, value: text(i + 2, finish - 1).strip)
          else
            finish = statement_end(i, stop)
            record_member(:field, last_word(from, i), modifiers, attrs, outer, start, header, i, finish, value: text(i + 1, finish - 1).strip)
          end
          return finish
        when ';'
          record_member(:field, last_word(from, i), modifiers, attrs, outer, start, header, i, i + 1)
          return i + 1
        when '}', ')', ']'
          return i
        end
        i += 1
      end
      stop
    end

    # The method name a `(` at `paren` follows (`Get`, `Get<T>`), or nil for
    # a tuple type or a keyword.
    private def callable_name(from : Int32, paren : Int32) : Tuple(String, Symbol)?
      j = paren - 1
      while j >= from && @m[j].whitespace?
        j -= 1
      end
      return if j < from
      if @m[j] == '>'
        depth = 0
        while j >= from
          depth += 1 if @m[j] == '>'
          depth -= 1 if @m[j] == '<'
          break if depth == 0
          j -= 1
        end
        j -= 1
        while j >= from && @m[j].whitespace?
          j -= 1
        end
      end
      return if j < from || !ident_char?(@m[j])
      finish = j + 1
      while j >= from && ident_char?(@m[j])
        j -= 1
      end
      name = masked_text(j + 1, finish)
      return if DECL_MODIFIER.includes?(name) || name.empty? || name[0].ascii_number?
      {name, j >= from && @m[j] == '~' ? :destructor : :method}
    end

    private def return_type_text(from : Int32, paren : Int32, name : String) : String
      head = text(from, paren)
      cut = head.rindex(name) || head.size
      head[0, cut].strip
    end

    private def last_word(from : Int32, to : Int32) : String
      head = masked_text(from, to).rstrip
      head.match(/([A-Za-z_\x{80}-\x{10FFFF}][\w\x{80}-\x{10FFFF}]*)\s*(?:\[[^\]]*\])?\s*\z/).try(&.[1]) || ""
    end

    private def finish_callable(start : Int32, header : Int32, modifiers : Array(String), from : Int32,
                                attrs : Array(Attribute), outer : TypeDecl?, stop : Int32,
                                paren : Int32, kind : Symbol, name : String) : Int32
      close = matching(paren, stop) || return stop
      head = text(from, paren)
      type_params = nil
      if (lt = head.rindex('<')) && head.rstrip.ends_with?('>') && kind == :method
        type_params = head[lt..].strip
        head = head[0, lt]
      end
      return_type = kind == :method ? return_type_text(from, from + head.size, name) : ""
      params = parse_params(paren, close)
      j = skip_ws(close + 1, stop)
      initializer = nil
      initializer_args = nil
      if @m[j]? == ':' && @m[j + 1]? != ':' && kind == :constructor
        k = skip_ws(j + 1, stop)
        if (ident = read_ident(k, stop)) && ident[0].in?("base", "this")
          k = skip_ws(ident[1], stop)
          if @m[k]? == '(' && (args_close = matching(k, stop))
            initializer = ident[0]
            initializer_args = parse_args(k + 1, args_close)
            j = skip_ws(args_close + 1, stop)
          end
        end
      end
      # Constraints (`where T : new()`) run to the body.
      while j < stop && !@m[j].in?('{', ';') && !(@m[j] == '=' && @m[j + 1]? == '>')
        break if @m[j].in?('}', ')')
        if @m[j] == '(' && (skip = matching(j, stop))
          j = skip + 1
        else
          j += 1
        end
      end
      body_open = nil
      body_close = nil
      arrow = nil
      finish = j
      if @m[j]? == '{'
        body_open = j
        body_close = matching(j, stop)
        finish = (body_close || stop - 1) + 1
      elsif @m[j]? == '='
        arrow = j
        finish = statement_end(j, stop)
      elsif @m[j]? == ';'
        finish = j + 1
      end
      if outer
        member = Member.new(kind, name, modifiers, attrs, return_type, type_params, params, initializer, initializer_args,
          line_of(start), line_of(header), line_of(close), line_of(Math.max(finish - 1, 0)),
          text(from, close + 1), body_open, body_close, arrow, finish, nil)
        outer.members << member
      end
      Math.max(finish, close + 1)
    end

    private def record_member(kind : Symbol, name : String, modifiers : Array(String), attrs : Array(Attribute),
                              outer : TypeDecl?, start : Int32, header : Int32, at : Int32, finish : Int32,
                              value : String? = nil, body : Tuple(Int32, Int32)? = nil) : Nil
      return unless outer
      head = text(header, at).strip
      outer.members << Member.new(kind, name, modifiers, attrs, "", nil, [] of Parameter, nil, nil,
        line_of(start), line_of(header), line_of(at), line_of(Math.max(finish - 1, 0)), head,
        nil, nil, nil, finish, value, body.try { |(open, close)| text(open, close + 1) })
    end

    # Splits `open+1...close` at the commas outside every bracket, as
    # `{start, end}` offsets.
    private def split_top(open : Int32, close : Int32, angles : Bool = false) : Array(Tuple(Int32, Int32))
      parts = [] of Tuple(Int32, Int32)
      depth = 0
      start = open
      i = open
      while i < close
        char = @m[i]
        case char
        when '(', '[', '{' then depth += 1
        when ')', ']', '}' then depth -= 1 if depth > 0
        when '<'
          depth += 1 if angles && i > 0 && ident_char?(@m[i - 1])
        when '>'
          depth -= 1 if angles && depth > 0 && !(@m[i - 1]? == '=')
        when ','
          if depth == 0
            parts << {start, i}
            start = i + 1
          end
        end
        i += 1
      end
      parts << {start, close} unless text(start, close).blank?
      parts
    end

    NAMED_ARG_RE    = /\A\s*@?([A-Za-z_]\w*)\s*:(?!:)/
    PROPERTY_ARG_RE = /\A\s*@?([A-Za-z_]\w*)\s*=(?![=>])/

    private def parse_args(open : Int32, close : Int32) : Array(Arg)
      split_top(open, close).map do |(from, to)|
        masked = masked_text(from, to)
        source = text(from, to)
        if m = masked.match(NAMED_ARG_RE)
          Arg.new(source[m.end(0)..].strip, name: m[1])
        elsif m = masked.match(PROPERTY_ARG_RE)
          Arg.new(source[m.end(0)..].strip, property: m[1])
        else
          Arg.new(source.strip)
        end
      end
    end

    TARGET_RE = /\A\s*([a-z]+)\s*:(?!:)/

    private def parse_attribute_list(open : Int32, close : Int32) : Array(Attribute)
      attrs = [] of Attribute
      from = open + 1
      target = nil
      if m = masked_text(from, close).match(TARGET_RE)
        target = m[1]
        from += m.end(0)
      end
      split_top(from, close).each do |(start, finish)|
        i = skip_ws(start, finish)
        name_start = i
        while i < finish && (ident_char?(@m[i]) || @m[i] == '.' || @m[i] == ':' || @m[i] == '@')
          i += 1
        end
        qualified = masked_text(name_start, i).strip
        next if qualified.empty?
        i = skip_ws(i, finish)
        if @m[i]? == '<' && (angle = matching_angle(i, finish))
          i = skip_ws(angle + 1, finish)
        end
        args = [] of Arg
        parens = false
        if i < finish && @m[i] == '(' && (args_close = matching(i, finish))
          args = parse_args(i + 1, args_close)
          parens = true
        end
        simple = CSharpDecl.simple_name(qualified)
        simple = simple.rchop("Attribute") unless simple == "Attribute"
        attrs << Attribute.new(simple, qualified, args, target, text(name_start, finish).strip, line_of(name_start), parens)
      end
      attrs
    end

    private def parse_params(open : Int32, close : Int32) : Array(Parameter)
      split_top(open + 1, close, angles: true).compact_map do |(from, to)|
        i = skip_ws(from, to)
        attrs = [] of Attribute
        while i < to && @m[i] == '['
          list_close = matching(i, to) || break
          attrs.concat(parse_attribute_list(i, list_close))
          i = skip_ws(list_close + 1, to)
        end
        modifiers = [] of String
        while (ident = read_ident(i, to)) && PARAM_MODIFIERS.includes?(ident[0])
          modifiers << ident[0]
          i = skip_ws(ident[1], to)
        end
        # The default value starts at the first `=` outside brackets.
        equals = nil
        depth = 0
        (i...to).each do |k|
          case @m[k]
          when '(', '[', '{', '<' then depth += 1
          when ')', ']', '}', '>' then depth -= 1 if depth > 0
          when '='
            if depth == 0 && @m[k + 1]? != '=' && @m[k + 1]? != '>' && @m[k - 1]? != '!'
              equals = k
              break
            end
          end
        end
        decl_end = equals || to
        decl = text(i, decl_end).rstrip
        name_match = decl.match(/(@?[A-Za-z_\x{80}-\x{10FFFF}][\w\x{80}-\x{10FFFF}]*)\z/) || next
        type = decl[0, name_match.begin(0)].strip
        default = equals.try { |pos| text(pos + 1, to).strip }
        Parameter.new(attrs, modifiers, type, name_match[1].lchop('@'), default, text(from, to).strip)
      end
    end
  end
end
