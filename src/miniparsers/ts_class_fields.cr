require "../utils/js_literal_scanner"
require "../utils/top_level_split"

module Noir
  # The property names a TypeScript class, interface or object type declares,
  # and the types it inherits them from. Built for request DTOs
  # (`@Body() body: CreateUserDto`): no file I/O, the caller resolves base
  # names to declarations.
  module TsClassFields
    # A type fields are inherited from: all of `name`'s, only `pick`, or all
    # but `omit` (Nest's `PickType` / `OmitType` mapped types).
    record Base, name : String, pick : Array(String)? = nil, omit : Array(String) = [] of String

    record Decl, fields : Array(String), bases : Array(Base)

    DECL_HEAD = /\b(?:class|interface)\s+([A-Za-z_$][\w$]*)\s*(?:<(?:[^<>{}]|<[^<>{}]*>)*>)?([^{;]*)\{/
    # A member head at the top level of a body whose nested `(...)`, `[...]`
    # and `{...}` were blanked: decorators, modifiers, then `name?:`,
    # `name!:`, `name =` or `name;`. A method (`name(`), accessor
    # (`get name(`), `static` or non-public member does not match.
    MEMBER = /(?:\A|[;,}\n])\s*(?:@[\w$.]+\s*(?:\(\s*\))?\s*)*(?:(?:public|readonly|declare|override)\s+)*([A-Za-z_$][\w$]*)\s*[?!]?\s*[:=;,\n]/
    MAPPED = /\A(PartialType|PickType|OmitType|IntersectionType|RequiredType)\s*\(/
    # A member whose value is a function (`handler = () => ...`,
    # `cb: (x) => void`) is behaviour, not request data.
    FUNCTION_VALUE = /\A\s*(?:async\s*)?(?:\(\s*\)|[A-Za-z_$][\w$]*)\s*(?::[^=;\n]*)?=>/
    # A line ending in one of these continues onto the next: `kind:\n Foo;`.
    CONTINUES = {':', '=', '|', '&', ',', '<', '(', '[', '?'}

    # Every class/interface declared in `code` (comments already stripped),
    # by name; the first declaration of a name wins.
    def self.declarations(code : String) : Hash(String, Decl)
      decls = {} of String => Decl
      code.scan(DECL_HEAD) do |m|
        next if decls.has_key?(m[1])
        open = m.end(0) - 1
        close = JSLiteralScanner.find_matching_brace(code, open) || next
        decls[m[1]] = Decl.new(members(code[(open + 1)...close]), heritage(m[2]))
      end
      # A zod object schema, the base of a nestjs-zod `createZodDto(X)` DTO.
      if code.includes?("z.")
        code.scan(ZOD_OBJECT_DECL) do |m|
          next if decls.has_key?(m[1])
          open = m.end(0) - 1
          close = JSLiteralScanner.find_matching_brace(code, open) || next
          decls[m[1]] = Decl.new(members(code[(open + 1)...close]), [] of Base)
        end
      end
      decls
    end

    ZOD_OBJECT_DECL = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]+)?=\s*z\s*\.\s*(?:object|strictObject|looseObject)\s*\(\s*\{/
    # nestjs-zod's `class X extends createZodDto(Schema) {}`.
    ZOD_DTO = /\AcreateZodDto\s*\(/

    # Property names of an inline object type `{ a: string; b?: number }`.
    def self.object_type_fields(type : String) : Array(String)
      text = type.strip
      return [] of String unless text.starts_with?('{') && text.ends_with?('}')
      members(text[1...-1])
    end

    def self.members(body : String) : Array(String)
      fields = [] of String
      text = top_level(body)
      text.scan(MEMBER) do |m|
        name = m[1]
        next if {"constructor", "static", "private", "protected", "get", "set", "async"}.includes?(name)
        # The match starts at the separator: what precedes it must end a member.
        before = text.byte_slice(0, m.byte_begin(0)).rstrip
        next if !before.empty? && (CONTINUES.includes?(before[-1]) || before.ends_with?("=>"))
        next if m[0].ends_with?('=') || m[0].ends_with?(':') ? text.byte_slice(m.byte_end(0)).matches?(FUNCTION_VALUE) : false
        fields << name unless fields.includes?(name)
      end
      fields
    end

    # `extends Base<T>`, `extends PickType(Base, ['a'] as const)`,
    # `extends IntersectionType(A, PartialType(B))`; interfaces may extend
    # several (`extends A, B`). `implements` names no fields.
    def self.heritage(header : String) : Array(Base)
      clause = header.match(/\bextends\s+([\s\S]*?)(?:\bimplements\b|\z)/).try(&.[1].strip) || return [] of Base
      TopLevelSplit.split(clause, ',', TopLevelSplit::Rules::JS).flat_map { |part| type_bases(part) }
    end

    def self.type_bases(expr : String) : Array(Base)
      text = expr.strip
      if m = text.match(MAPPED)
        close = JSLiteralScanner.find_matching_paren(text, m.end(0) - 1) || return [] of Base
        args = TopLevelSplit.split(text[m.end(0)...close], ',', TopLevelSplit::Rules::JS)
        return args.flat_map { |arg| type_bases(arg) } if m[1] == "IntersectionType"
        bases = type_bases(args[0]? || "")
        keys = args[1]?.try { |arg| arg.scan(/['"`]([^'"`]+)['"`]/).map(&.[1]) }
        return bases.map { |base| Base.new(base.name, keys, base.omit) } if m[1] == "PickType" && keys
        return bases.map { |base| Base.new(base.name, base.pick, base.omit + keys) } if m[1] == "OmitType" && keys
        return bases
      end
      if m = text.match(ZOD_DTO)
        close = JSLiteralScanner.find_matching_paren(text, m.end(0) - 1) || return [] of Base
        return type_bases(text[m.end(0)...close])
      end
      name = text.match(/\A([A-Za-z_$][\w$.]*)/).try(&.[1]) || return [] of Base
      [Base.new(name.split('.').last)]
    end

    # `body` with the contents of every nested bracket pair, top-level type
    # argument list (`Array<\n Ref\n>`) and string blanked (newlines kept),
    # so only the body's own member heads remain.
    private def self.top_level(body : String) : String
      String.build(body.bytesize) do |io|
        depth = 0
        angle = 0
        previous = ' '
        quote : Char? = nil
        escaped = false
        body.each_char do |char|
          last = previous
          previous = char
          if quote
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == quote
              quote = nil
            end
            io << (char == '\n' ? '\n' : ' ')
            next
          end
          if depth == 0 && (char == '<' || angle > 0)
            if char == '<'
              angle += 1
            elsif char == '>' && last != '='
              angle -= 1
            end
            io << (char == '\n' ? '\n' : ' ')
            next
          end
          case char
          when '\'', '"', '`'
            quote = char
            io << ' '
          when '(', '[', '{'
            io << (depth == 0 ? char : ' ')
            depth += 1
          when ')', ']', '}'
            depth -= 1 if depth > 0
            io << (depth == 0 ? char : ' ')
          else
            io << (depth > 0 && char != '\n' ? ' ' : char)
          end
        end
      end
    end
  end
end
