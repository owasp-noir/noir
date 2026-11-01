module Noir
  class RailsCallbackChain
    # The line reader the AST reader replaced, kept for a file tree-sitter
    # cannot shape into classes: one whose `class` / `module` sits in an
    # ERROR node (a syntax error elsewhere in ApplicationController), or one
    # that fails to parse at all. Dropping such a file would drop every
    # callback a parent controller registers. It reads indentation and
    # regexes, so heredocs and line shapes fool it the way they always did.
    private class LineReader
      LIST_TERM  = /((?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\.[a-z_]\w*)(?:\.map\s*\{\s*\|(\w+)\|\s*:?"([^"]*)"\s*\})?/
      MACRO_CALL = /\A[a-z_]\w*[!?]?(?:\s+[^=\s]|\(|\z)/

      @classes = [] of {Int32, Klass}
      @defs = [] of {String, Int32}
      @macros = [] of {String, ClassMacro}
      @statements = Hash(Int32, String).new
      @class_rows = Set(Int32).new
      @splat_defs = Hash(String, String).new

      def initialize(@path : String, @resolver : Proc(String, Noir::RubyConstantList::Result?)?)
      end

      def read(lines : Array(String)) : Facts
        @splat_defs = splat_defs_of(lines)
        stack = [] of {Klass, Int32}
        def_indent : Int32? = nil
        macro_body : Array(String)? = nil
        # A concern's `class_methods do` (or `class << self`) block: the
        # `def`s in it are class macros, as `def self.x` is.
        class_methods_indent : Int32? = nil
        # The `if` / `unless` blocks open around a macro body line, as the
        # `if:` / `unless:` option the line then carries.
        macro_conditions = [] of {Int32, String}
        lines.each_with_index do |line, idx|
          stripped = line.strip
          next if stripped.empty? || stripped.starts_with?('#')
          indent = line.size - line.lstrip.size
          if open_def = def_indent
            if indent <= open_def && stripped == "end"
              def_indent = nil
            elsif body = macro_body
              while (open = macro_conditions.last?) && (indent < open[0] || (indent == open[0] && !stripped.matches?(/\A(?:else|elsif|when)\b/)))
                macro_conditions.pop
              end
              if m = stripped.match(/\A(if|unless|case)\s+(.+)/)
                macro_conditions << {indent, m[1] == "unless" ? "unless: -> { #{m[2]} }" : "if: -> { #{m[2]} }"}
              elsif stripped.matches?(CALLBACK_LINE)
                body << conditional_line(expand_lists(RailsCallbackChain.statement(lines, idx)), macro_conditions.last?.try(&.[1]))
              end
            end
            next
          end
          if (open_block = class_methods_indent) && indent <= open_block
            class_methods_indent = nil
            next if stripped == "end"
          end
          if stripped.matches?(/\A(?:class_methods\s+do|class\s*<<\s*self)\b/)
            class_methods_indent = indent
            next
          end
          while (top = stack.last?) && top[1] >= indent
            stack.pop
          end
          if m = stripped.match(/^(?:class|module)\s+([A-Z][\w:]*)(?:\s*<\s*([\w:]+))?/)
            namespace = stack.last?.try(&.[0].name) || ""
            full = namespace.empty? ? m[1] : "#{namespace}::#{m[1]}"
            klass = Klass.new(full, namespace, m[2]?, @path)
            @classes << {idx, klass}
            @class_rows << idx if stripped.starts_with?("class")
            stack << {klass, indent}
          elsif m = stripped.match(/^def\s+(self\.)?(\w+[!?]?)/)
            @defs << {m[2], idx}
            def_indent = indent unless stripped.matches?(/\bend$|^def\s+[\w.?!]+(?:\([^)]*\))?\s*=[^=]/)
            macro_body = nil
            macro_conditions.clear
            if (m[1]? || class_methods_indent) && def_indent
              macro_body = [] of String
              param = stripped.match(/\A[^(]*\(\s*\*{0,2}(\w+)/).try(&.[1])
              @macros << {m[2], ClassMacro.new(@path, param.try { |name| /\s*,\s*\*{0,2}#{name}\b/ },
                param.try { |name| /(?<![\w@:])\*{0,2}#{name}\b/ }, macro_body)}
            end
          elsif (top = stack.last?) && (stripped.matches?(CALLBACK_LINE) || stripped.matches?(MACRO_CALL))
            # A class macro the app may define (`requires_login`) is kept for
            # `apply_lines`, which expands it once every file is indexed.
            text = expand_lists(RailsCallbackChain.statement(lines, idx))
            top[0].callbacks << text
            @statements[idx] = text
          end
        end
        Facts.new(@classes, @defs, @macros, @statements, @class_rows, Hash(Int32, Int32).new, [] of {Int32, Int32}, false)
      end

      # A macro body line under a condition carries it as an `if:` / `unless:` option.
      private def conditional_line(text : String, block : String?) : String
        if m = text.match(/\s+(if|unless)\s+(.+)\z/)
          text = text[0, m.begin(0)]
          block ||= "#{m[1]}: -> { #{m[2]} }"
        end
        block ? "#{text}, #{block}" : text
      end

      # Names an `only:` / `except:` list spells through a list another file
      # defines, or a `*splat` of this file's `def self.x`, as symbols.
      private def expand_lists(text : String) : String
        return text unless (resolver = @resolver) && (text.includes?("only:") || text.includes?("except:"))
        expand = ->(source : String) do
          source.gsub(LIST_TERM) do |term, match|
            next term unless list = resolver.call(match[1])
            names = if template = match[3]?
                      list.values.map { |value| template.gsub(/\#\{\s*#{Regex.escape(match[2])}\s*\}/, value) }
                    else
                      list.values
                    end
            names.join(", ") { |name| ":#{name}" }
          end
        end
        text = text.gsub(/\*(\w+)/) do |splat, match|
          next splat unless body = @splat_defs[match[1]]?
          expanded = expand.call(body)
          expanded.matches?(LIST_TERM) ? splat : expanded
        end
        expand.call(text)
      end

      # The one-expression bodies of this file's `def self.name` methods.
      private def splat_defs_of(lines : Array(String)) : Hash(String, String)
        defs = Hash(String, String).new
        lines.each_with_index do |line, idx|
          next unless m = line.match(/^(\s*)def\s+self\.(\w+)\b/)
          body = [] of String
          ((idx + 1)...lines.size).each do |j|
            break if lines[j].strip.empty? ? false : (lines[j].size - lines[j].lstrip.size) <= m[1].size
            body << lines[j].strip unless lines[j].strip.empty?
          end
          defs[m[2]] = body.join(" ")
        end
        defs
      end
    end
  end
end
