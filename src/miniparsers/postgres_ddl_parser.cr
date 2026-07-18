module Noir
  # Minimal PostgreSQL DDL reader, enough to recover the table/column
  # shape a PostgREST-style API is generated from.
  #
  # Migrations are a *sequence*, not a set: a column added in the third
  # file and dropped in the fifth is not part of the final surface. So
  # statements are applied onto a `State` that callers thread through
  # every file in order.
  #
  # The parse is three passes:
  #
  #   1. Mask comments and string bodies, preserving byte positions and
  #      newlines so later passes can still slice and count lines.
  #   2. Split on top-level `;` (paren depth 0).
  #   3. Match statement headers, and split the column list on top-level
  #      commas so `numeric(10,2)`, `check (a > 0)` and `references t(id)`
  #      survive.
  #
  # Dollar-quoted bodies (`$$ ... $$`) are masked in pass 1 — function
  # bodies routinely contain both `create table` text and semicolons, and
  # without this a single function definition would shred the split.
  module PostgresDdlParser
    extend self

    # Table-level constraints, not columns.
    CONSTRAINT_KEYWORDS = Set{
      "primary", "foreign", "unique", "check", "constraint",
      "exclude", "like", "inherits", "partition",
    }

    # Terminate the type when one of these begins the column's constraints.
    TYPE_TERMINATORS = Set{
      "not", "null", "default", "primary", "references", "unique",
      "check", "generated", "collate", "constraint", "on", "deferrable",
      "identity", "always", "storage", "compression",
    }

    TYPE_HINTS = {
      "text" => "string", "varchar" => "string", "character" => "string",
      "char" => "string", "uuid" => "string", "citext" => "string",
      "name" => "string", "bytea" => "string", "inet" => "string",
      "cidr" => "string", "macaddr" => "string", "xml" => "string",
      "int" => "int", "int2" => "int", "int4" => "int", "int8" => "int",
      "integer" => "int", "smallint" => "int", "bigint" => "int",
      "serial" => "int", "bigserial" => "int", "smallserial" => "int",
      "numeric" => "number", "decimal" => "number", "real" => "number",
      "double" => "number", "float" => "number", "float4" => "number",
      "float8" => "number", "money" => "number",
      "bool" => "boolean", "boolean" => "boolean",
      "timestamp" => "datetime", "timestamptz" => "datetime",
      "date" => "datetime", "time" => "datetime", "timetz" => "datetime",
      "interval" => "datetime",
      "json" => "object", "jsonb" => "object",
    }

    struct Column
      getter name : String
      getter type : String

      def initialize(@name : String, @type : String)
      end

      def hint : String
        base = @type.downcase
        return "array" if base.ends_with?("[]")
        base = base.split('(').first.strip
        base = base.split(' ').first
        TYPE_HINTS[base]? || ""
      end
    end

    class Table
      property schema : String
      property name : String
      property columns : Array(Column)
      property? view : Bool
      property source : String
      property line : Int32

      def initialize(@schema, @name, @columns = [] of Column,
                     @view = false, @source = "", @line = 0)
      end

      def qualified : String
        "#{@schema}.#{@name}"
      end
    end

    struct Function
      getter schema : String
      getter name : String
      getter arguments : Array(Column)
      getter source : String
      getter line : Int32

      def initialize(@schema, @name, @arguments, @source, @line)
      end
    end

    # Accumulates the effect of every statement seen so far.
    class State
      getter tables : Hash(String, Table)
      getter functions : Hash(String, Function)

      def initialize
        @tables = {} of String => Table
        @functions = {} of String => Function
      end
    end

    DEFAULT_SCHEMA = "public"

    # Applies every statement in `content` onto `state`.
    def apply(content : String, source : String, state : State) : Nil
      masked = mask(content)

      each_statement(masked) do |start, finish, line|
        statement = masked[start...finish]
        next if statement.blank?

        # Comments were masked to spaces in pass 1, so the first
        # non-whitespace character is the statement keyword. Skipping the
        # blank lead makes the reported line point there rather than at a
        # comment sitting above it.
        lead = 0
        offset = 0
        while offset < statement.size && statement[offset].whitespace?
          lead += 1 if statement[offset] == '\n'
          offset += 1
        end

        apply_statement(statement, source, line + lead, state)
      end
    end

    # Convenience for a single self-contained document.
    def parse(content : String, source : String = "") : State
      state = State.new
      apply(content, source, state)
      state
    end

    # ---- pass 1: masking --------------------------------------------

    # Replaces comment and string bodies with spaces. Positions and
    # newlines are preserved so statement offsets and line numbers stay
    # valid against the original text.
    private def mask(content : String) : String
      chars = content.chars
      size = chars.size
      i = 0

      while i < size
        c = chars[i]

        case
        when c == '-' && i + 1 < size && chars[i + 1] == '-'
          while i < size && chars[i] != '\n'
            chars[i] = ' '
            i += 1
          end
        when c == '/' && i + 1 < size && chars[i + 1] == '*'
          # Postgres block comments nest.
          depth = 0
          while i < size
            if chars[i] == '/' && i + 1 < size && chars[i + 1] == '*'
              depth += 1
              chars[i] = ' '
              chars[i + 1] = ' '
              i += 2
            elsif chars[i] == '*' && i + 1 < size && chars[i + 1] == '/'
              depth -= 1
              chars[i] = ' '
              chars[i + 1] = ' '
              i += 2
              break if depth == 0
            else
              chars[i] = ' ' unless chars[i] == '\n'
              i += 1
            end
          end
        when c == '\''
          i += 1
          while i < size
            if chars[i] == '\'' && i + 1 < size && chars[i + 1] == '\''
              chars[i] = ' '
              chars[i + 1] = ' '
              i += 2
              next
            end
            break if chars[i] == '\''
            chars[i] = ' ' unless chars[i] == '\n'
            i += 1
          end
          i += 1 if i < size
        when c == '$'
          if tag = dollar_tag(chars, i, size)
            close = find_dollar_close(chars, i + tag.size, size, tag)
            finish = close || size
            j = i
            while j < finish
              chars[j] = ' ' unless chars[j] == '\n'
              j += 1
            end
            i = close ? close + tag.size : size
          else
            i += 1
          end
        else
          i += 1
        end
      end

      String.build(size) { |io| chars.each { |ch| io << ch } }
    end

    # `$$` or `$name$` at `start`, else nil.
    private def dollar_tag(chars : Array(Char), start : Int32, size : Int32) : String?
      j = start + 1
      while j < size && (chars[j].alphanumeric? || chars[j] == '_')
        j += 1
      end
      return unless j < size && chars[j] == '$'
      String.build { |io| (start..j).each { |k| io << chars[k] } }
    end

    private def find_dollar_close(chars : Array(Char), from : Int32, size : Int32, tag : String) : Int32?
      tag_chars = tag.chars
      limit = size - tag_chars.size
      j = from
      while j <= limit
        matched = true
        tag_chars.each_with_index do |tc, k|
          if chars[j + k] != tc
            matched = false
            break
          end
        end
        return j if matched
        j += 1
      end
      nil
    end

    # ---- pass 2: statement split ------------------------------------

    # Yields `(start, finish, line)`. The line is tracked as we go so a
    # long migration does not pay a rescan per statement.
    private def each_statement(masked : String, &)
      depth = 0
      start = 0
      line = 1
      start_line = 1

      masked.each_char_with_index do |c, i|
        case c
        when '\n'
          line += 1
        when '(' then depth += 1
        when ')' then depth -= 1 if depth > 0
        when ';'
          if depth == 0
            yield start, i, start_line
            start = i + 1
            start_line = line
          end
        end
      end

      yield start, masked.size, start_line if start < masked.size
    end

    # ---- pass 3: statement dispatch ---------------------------------

    CREATE_TABLE = /\A\s*create\s+(?:global\s+|local\s+|temp(?:orary)?\s+|unlogged\s+)*table\s+(?:if\s+not\s+exists\s+)?([^\s(]+)/i
    CREATE_VIEW  = /\A\s*create\s+(?:or\s+replace\s+)?(?:materialized\s+)?view\s+(?:if\s+not\s+exists\s+)?([^\s(]+)/i
    CREATE_FUNC  = /\A\s*create\s+(?:or\s+replace\s+)?function\s+([^\s(]+)\s*\(/i
    ALTER_TABLE  = /\A\s*alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?([^\s(]+)\s+(.*)\z/im
    DROP_TABLE   = /\A\s*drop\s+table\s+(?:if\s+exists\s+)?(.+?)(?:\s+cascade|\s+restrict)?\s*\z/im

    private def apply_statement(statement : String, source : String, line : Int32, state : State)
      if match = CREATE_TABLE.match(statement)
        schema, name = split_qualified(match[1])
        columns = column_list(statement).compact_map { |item| parse_column(item) }
        state.tables["#{schema}.#{name}"] = Table.new(schema, name, columns, false, source, line)
        return
      end

      if match = CREATE_VIEW.match(statement)
        schema, name = split_qualified(match[1])
        state.tables["#{schema}.#{name}"] = Table.new(schema, name, [] of Column, true, source, line)
        return
      end

      if match = CREATE_FUNC.match(statement)
        schema, name = split_qualified(match[1])
        args = function_arguments(statement).compact_map { |item| parse_argument(item) }
        state.functions["#{schema}.#{name}"] = Function.new(schema, name, args, source, line)
        return
      end

      if match = DROP_TABLE.match(statement)
        match[1].split(',').each do |raw|
          schema, name = split_qualified(raw.strip)
          state.tables.delete("#{schema}.#{name}")
        end
        return
      end

      if match = ALTER_TABLE.match(statement)
        schema, name = split_qualified(match[1])
        apply_alter(state, "#{schema}.#{name}", match[2])
      end
    end

    ADD_COLUMN    = /\Aadd\s+(?:column\s+)?(?:if\s+not\s+exists\s+)?(.+)\z/im
    DROP_COLUMN   = /\Adrop\s+(?:column\s+)?(?:if\s+exists\s+)?([^\s,]+)/i
    RENAME_COLUMN = /\Arename\s+(?:column\s+)?([^\s]+)\s+to\s+([^\s,]+)/i
    RENAME_TABLE  = /\Arename\s+to\s+([^\s,]+)/i

    private def apply_alter(state : State, key : String, action : String)
      table = state.tables[key]?
      return unless table
      action = action.strip

      if match = RENAME_TABLE.match(action)
        renamed = unquote(match[1])
        state.tables.delete(key)
        table.name = renamed
        state.tables[table.qualified] = table
        return
      end

      if match = RENAME_COLUMN.match(action)
        from = unquote(match[1])
        to = unquote(match[2])
        table.columns = table.columns.map do |column|
          column.name == from ? Column.new(to, column.type) : column
        end
        return
      end

      if match = DROP_COLUMN.match(action)
        dropped = unquote(match[1])
        table.columns.reject! { |column| column.name == dropped }
        return
      end

      if match = ADD_COLUMN.match(action)
        # `ADD CONSTRAINT ...` is not a column.
        return if match[1].lstrip.downcase.starts_with?("constraint")
        if column = parse_column(match[1])
          table.columns << column unless table.columns.any? { |c| c.name == column.name }
        end
      end
    end

    # ---- column list ------------------------------------------------

    # The balanced paren block after the table name, split on top-level
    # commas. The depth counter is what keeps `numeric(10,2)` and
    # `references other(id)` intact.
    private def column_list(statement : String) : Array(String)
      open = statement.index('(')
      return [] of String unless open

      items = [] of String
      depth = 0
      current = String::Builder.new
      i = open

      while i < statement.size
        c = statement[i]
        case c
        when '('
          depth += 1
          current << c if depth > 1
        when ')'
          depth -= 1
          if depth == 0
            items << current.to_s
            break
          end
          current << c
        when ','
          if depth == 1
            items << current.to_s
            current = String::Builder.new
          else
            current << c
          end
        else
          current << c
        end
        i += 1
      end

      items.map(&.strip).reject(&.empty?)
    end

    private def parse_column(item : String) : Column?
      tokens = item.strip.split(/\s+/)
      return if tokens.empty?
      return if CONSTRAINT_KEYWORDS.includes?(tokens[0].downcase)

      name = unquote(tokens[0])
      return if name.empty?

      type_tokens = [] of String
      tokens[1..].each do |token|
        break if TYPE_TERMINATORS.includes?(token.downcase)
        type_tokens << token
      end

      type = type_tokens.join(' ')
      # A generated-always-stored column cannot be written.
      return if item.matches?(/\bgenerated\s+always\s+as\s*\(/i)

      Column.new(name, type)
    end

    private def function_arguments(statement : String) : Array(String)
      column_list(statement)
    end

    # `IN name type`, `name type DEFAULT x`, or a bare type.
    private def parse_argument(item : String) : Column?
      tokens = item.strip.split(/\s+/)
      return if tokens.empty?

      tokens.shift if {"in", "out", "inout", "variadic"}.includes?(tokens[0].downcase)
      return if tokens.size < 2

      name = unquote(tokens[0])
      return if name.empty?

      type_tokens = [] of String
      tokens[1..].each do |token|
        break if token.downcase == "default" || token == "="
        type_tokens << token
      end

      Column.new(name, type_tokens.join(' '))
    end

    # ---- identifiers ------------------------------------------------

    private def split_qualified(raw : String) : Tuple(String, String)
      cleaned = raw.strip.rstrip(';')
      parts = cleaned.split('.')
      if parts.size >= 2
        {unquote(parts[-2]), unquote(parts[-1])}
      else
        {DEFAULT_SCHEMA, unquote(cleaned)}
      end
    end

    private def unquote(raw : String) : String
      value = raw.strip.rstrip(',').rstrip(';')
      if value.size >= 2 && value[0] == '"' && value[-1] == '"'
        value[1..-2]
      else
        value
      end
    end
  end
end
