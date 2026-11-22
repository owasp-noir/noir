require "./csharp_decl_parser"

module Noir
  # A handler body starts at its first statement (or opening brace). Its
  # registration and declaration can be in different files.
  record CSharpHandlerDeclaration, parameters : String, body : String, body_line : Int32, line : Int32

  class CSharpHandlerDeclarations
    getter unit : CSharpDecl::Unit
    @starts = [0]

    def initialize(@lexer : CSharpLexer)
      @unit = CSharpDeclParser.parse(@lexer)
      @lexer.masked.each_with_index { |char, index| @starts << index + 1 if char == '\n' }
    end

    def method(member : CSharpDecl::Member) : CSharpHandlerDeclaration?
      start = member.body_open || member.arrow.try(&.+(2)) || return
      CSharpHandlerDeclaration.new(member.params.join(", ", &.text),
        @lexer.code_source[start...member.finish], line_of(start), member.line + 1)
    end

    # Local functions aren't type members. A declaration is visible only
    # inside its enclosing block, including statements before it.
    def local(name : String, call_line : Int32) : CSharpHandlerDeclaration?
      call = @starts[call_line]? || return
      found = nil
      nearest = -2
      masked = @lexer.masked_source
      masked.scan(/\b#{Regex.escape(name)}\s*\(/) do |match|
        open = match.end - 1
        close = @lexer.matching_delimiter(open) || next
        start = close + 1
        chars = @lexer.masked
        while chars[start]?.try(&.whitespace?)
          start += 1
        end
        next unless chars[start]? == '{' || (chars[start]? == '=' && chars[start + 1]? == '>')
        decl_line = line_of(open)
        next if @unit.member_at(decl_line - 1).try { |member| member.name == name }
        parent = enclosing_brace(match.begin)
        next if parent < nearest
        next if parent >= 0 && !(parent..(@lexer.matching_delimiter(parent) || chars.size)).includes?(call)
        finish = if chars[start] == '{'
                   (@lexer.matching_delimiter(start) || next) + 1
                 else
                   start += 2
                   @lexer.statement_end(start)
                 end
        nearest = parent
        found = CSharpHandlerDeclaration.new(@lexer.code_source[open + 1...close], @lexer.code_source[start...finish], line_of(start), decl_line)
      end
      found
    end

    private def enclosing_brace(offset : Int32) : Int32
      depth = 0
      (offset - 1).downto(0) do |index|
        case @lexer.masked[index]
        when '}' then depth += 1
        when '{'
          return index if depth == 0
          depth -= 1
        end
      end
      -1
    end

    private def line_of(offset)
      @starts.bsearch_index { |start| start > offset } || @starts.size
    end
  end
end
