require "../models/endpoint"
require "./callee_extractor_base"
require "../minilexers/php_lexer"

module Noir::PhpCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "array", "catch", "class", "clone", "declare", "die", "echo",
    "elseif", "empty", "eval", "exit", "fn", "for", "foreach",
    "function", "global", "if", "include", "include_once", "isset",
    "list", "match", "print", "require", "require_once", "return",
    "static", "switch", "throw", "trait", "try", "unset", "use", "while",
  }

  CLASS_PROPERTY_CALL_REGEX = /(\\?[A-Za-z_]\w*(?:\\[A-Za-z_]\w*)*::\$\w+(?:\s*->\s*[A-Za-z_]\w*\s*(?:\(\s*\))?)*\s*->\s*[A-Za-z_]\w*)\s*\(/
  OBJECT_CALL_REGEX         = /(?<!:)(\$[A-Za-z_]\w*(?:\s*->\s*[A-Za-z_]\w*\s*(?:\(\s*\))?)*\s*->\s*[A-Za-z_]\w*)\s*\(/
  STATIC_CALL_REGEX         = /(\\?[A-Za-z_]\w*(?:\\[A-Za-z_]\w*)*(?:::[A-Za-z_]\w*)+)\s*\(/
  BARE_CALL_REGEX           = /(?<![>\w:$\\])(\\?[A-Za-z_]\w*(?:\\[A-Za-z_]\w*)*)\s*\(/

  # `body` is a fragment of PHP code (a method or closure body) unless
  # `php_mode` is false, for a whole file that may open with markup.
  def callees_for_body(body : String, file_path : String, start_line : Int32, php_mode : Bool = true) : Array(Entry)
    entries = [] of Entry
    code_lines(body, php_mode).each_with_index do |line, index|
      scan_line(line, file_path, start_line + index, entries)
    end
    entries.uniq
  end

  # `content` with `//`, `#` and `/* */` comments (docblocks too) blanked,
  # string literals and `#[Attribute]`s kept, and every line in place.
  def strip_comments(content : String) : String
    Noir::PhpLexer.new(content).without_comments(keep_docblocks: false)
  end

  # The lines of `body` with strings, comments, heredocs and attributes
  # blanked, so a call written inside any of them (a multi-line SQL literal,
  # a heredoc template) is not a callee.
  private def code_lines(body : String, php_mode : Bool) : Array(String)
    lexer = Noir::PhpLexer.new(body, php_mode: php_mode)
    masked = lexer.masked
    i = 0
    while i + 1 < masked.size
      if masked[i] == '#' && masked[i + 1] == '[' && (close = lexer.matching_delimiter(i + 1))
        (i..close).each { |k| masked[k] = ' ' unless masked[k] == '\n' }
        i = close
      end
      i += 1
    end
    masked.join.split('\n')
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    # All four call patterns require `(` after the callee name. Pure
    # assignment / property lines cannot produce a callee.
    return unless line.includes?('(')

    if line.includes?("::") || line.includes?("->")
      line.scan(CLASS_PROPERTY_CALL_REGEX) do |match|
        name = normalize_call(match[1])
        next if skip_callee?(name)

        entries << {name, file_path, line_number}
      end

      if line.includes?("->")
        line.scan(OBJECT_CALL_REGEX) do |match|
          name = normalize_call(match[1])
          next if skip_callee?(name)

          entries << {name, file_path, line_number}
        end
      end

      if line.includes?("::")
        line.scan(STATIC_CALL_REGEX) do |match|
          name = normalize_call(match[1])
          next if skip_callee?(name)

          entries << {name, file_path, line_number}
        end
      end
    end

    line.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      next if declaration_name?(line, match.begin(1))
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def declaration_name?(line : String, name_start : Int32?) : Bool
    return false unless name_start

    line[0...name_start].match(/\bfunction\s*&?\s*$/) ? true : false
  end

  private def normalize_call(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?
    return false if name.includes?("->") || name.includes?("::")

    RESERVED.includes?(name.downcase)
  end
end
