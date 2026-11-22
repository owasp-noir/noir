module Noir
  module TsClassFields
    # A member head at the top level of a body whose nested `(...)`, `[...]`
    # and `{...}` were blanked: decorators, modifiers, then `name?:`,
    # `name!:`, `name =` or `name;`. A method (`name(`), accessor
    # (`get name(`), `static` or non-public member does not match.
    MEMBER = /(?:\A|[;,}\n])\s*(?:@[\w$.]+\s*(?:\(\s*\))?\s*)*(?:(?:public|readonly|declare|override)\s+)*([A-Za-z_$][\w$]*)\s*[?!]?\s*[:=;,\n]/
    # A member whose value is a function (`handler = () => ...`,
    # `cb: (x) => void`) is behaviour, not request data.
    FUNCTION_VALUE = /\A\s*(?:async\s*)?(?:\(\s*\)|[A-Za-z_$][\w$]*)\s*(?::[^=;\n]*)?=>/
    # A line ending in one of these continues onto the next: `kind:\n Foo;`.
    CONTINUES = {':', '=', '|', '&', ',', '<', '(', '[', '?'}

    ZOD_OBJECT_DECL = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]+)?=\s*z\s*\.\s*(?:object|strictObject|looseObject)\s*\(\s*\{/

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
