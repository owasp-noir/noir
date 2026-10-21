module Noir
  # The `before_action` chain a Rails action runs. A controller's own class
  # body is only half of it: `before_action :authenticate_user!` usually sits
  # in ApplicationController, and `rails generate authentication` (Rails 8)
  # installs `before_action :require_authentication` through an
  # `Authentication` concern ApplicationController includes. Shared by the
  # Rails analyzer (header/cookie reads in callbacks) and the auth tagger
  # (whether a callback guards the action).
  class RailsCallbackChain
    # A Ruby class or module under a `controllers` directory, with the
    # class-body lines that touch the callback chain (`CALLBACK_LINE`).
    record Klass, name : String, namespace : String, parent : String?, path : String, callbacks : Array(String) = [] of String

    # The callbacks left active for an action, in registration order, and
    # the files of the classes/modules it passed through, nearest first
    # (where Ruby looks a callback's `def` up).
    record Resolution, callbacks : Array(String), paths : Array(String)

    # Class-body lines that change the callback chain a subclass inherits.
    CALLBACK_LINE = /^(?:include|(?:prepend_|skip_)?before_action|allow_unauthenticated_access)\b/

    ONLY_OPTION   = /\bonly:/
    EXCEPT_OPTION = /\bexcept:/

    getter classes = Hash({String, Int32}, Klass).new
    getter defs = Hash(String, Array({String, Int32})).new
    @by_name = Hash(String, Array(Klass)).new
    @by_path = Hash(String, Array(Klass)).new

    def self.applies_to_action?(line : String, action : String?) : Bool
      if only = callback_option(line, ONLY_OPTION)
        return !!(action && only.includes?(action))
      end
      if except = callback_option(line, EXCEPT_OPTION)
        return !(action && except.includes?(action))
      end
      true
    end

    # The action names an `only:` / `except:` option lists, in any of its
    # spellings: `:show`, `[:show, :edit]`, `%i[show edit]`, `"show"`.
    # Matching `":#{action}"` against the raw line missed the `%i[ new create ]`
    # the Rails generators write, and let `:new` match `:new_session`.
    def self.callback_option(line : String, option : Regex) : Array(String)?
      match = line.match(option)
      return unless match
      value = line[match.end..]
      if stop = value.index(/\b\w+:(?!:)/)
        value = value[0, stop]
      end
      value.gsub(/%[iwIW][\[(]/, " ").scan(/\w+[?!]?/).map(&.[0])
    end

    # Indexes every class and module `lines` declares, with its class-body
    # callback lines. Lines inside a `def` are not class-body: the
    # `Authentication` concern's own `def allow_unauthenticated_access` wraps
    # a `skip_before_action` that runs only when a controller calls it.
    def add_file(path : String, lines : Array(String))
      stack = [] of {Klass, Int32}
      def_indent : Int32? = nil
      lines.each_with_index do |line, idx|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')
        indent = line.size - line.lstrip.size
        if open_def = def_indent
          def_indent = nil if indent <= open_def && stripped == "end"
          next
        end
        while (top = stack.last?) && top[1] >= indent
          stack.pop
        end
        if m = stripped.match(/^(?:class|module)\s+([A-Z][\w:]*)(?:\s*<\s*([\w:]+))?/)
          namespace = stack.last?.try(&.[0].name) || ""
          full = namespace.empty? ? m[1] : "#{namespace}::#{m[1]}"
          klass = Klass.new(full, namespace, m[2]?, path)
          @classes[{path, idx}] = klass
          (@by_name[full] ||= [] of Klass) << klass
          (@by_path[path] ||= [] of Klass) << klass
          stack << {klass, indent}
        elsif m = stripped.match(/^def\s+(?:self\.)?(\w+[!?]?)/)
          (@defs[m[1]] ||= [] of {String, Int32}) << {path, idx}
          def_indent = indent unless stripped.matches?(/\bend$|^def\s+[\w.?!]+(?:\([^)]*\))?\s*=[^=]/)
        elsif (top = stack.last?) && stripped.matches?(CALLBACK_LINE)
          top[0].callbacks << stripped
        end
      end
    end

    # The controller class `path` declares.
    # ponytail: the first `*Controller` class in the file; a file holding
    # two controllers resolves both to the first.
    def controller_in(path : String) : Klass?
      @by_path[path]?.try &.find(&.name.ends_with?("Controller"))
    end

    # Ruby resolves a bare constant from the innermost namespace outwards. Two
    # definitions of one name (reopened, or the same name in two apps of a
    # monorepo) are ambiguous and resolve to nothing.
    def lookup(name : String, namespace : String) : Klass?
      name = name.lchop("::")
      scopes = namespace.split("::", remove_empty: true)
      scopes.size.downto(0) do |n|
        full = (scopes[0, n] + [name]).join("::")
        if found = @by_name[full]?
          return found.size == 1 ? found.first : nil
        end
      end
      nil
    end

    # What `leaf`'s parent chain, its concerns and its own class body leave
    # active for `action`, honouring `skip_before_action` /
    # `allow_unauthenticated_access` and their `only:` / `except:` lists. The
    # leaf's own callbacks run last, so its skips remove what the parents
    # registered. A parent outside the scan (`Devise::SessionsController`)
    # ends the chain.
    def resolve(leaf : Klass, action : String?) : Resolution
      active = [] of String
      paths = [] of String
      apply_ancestor(leaf, action, active, paths, 0)
      Resolution.new(active, paths.reverse.uniq!)
    end

    private def apply_ancestor(klass : Klass?, action : String?, active : Array(String), paths : Array(String), depth : Int32)
      return unless klass && depth < 16
      if parent = klass.parent
        apply_ancestor(lookup(parent, klass.namespace), action, active, paths, depth + 1)
      end
      apply_callbacks(klass, action, active, paths, depth)
    end

    private def apply_callbacks(klass : Klass, action : String?, active : Array(String), paths : Array(String), depth : Int32)
      klass.callbacks.each do |line|
        if line.starts_with?("include")
          line.scan(/[A-Z][\w:]*/) do |m|
            if (mod = lookup(m[0], klass.namespace)) && depth < 16
              apply_callbacks(mod, action, active, paths, depth + 1)
            end
          end
        elsif line.starts_with?("allow_unauthenticated_access")
          active.delete("require_authentication") if RailsCallbackChain.applies_to_action?(line, action)
        elsif m = line.match(/^(skip_)?\w*before_action\s+((?::\w+[!?]?\s*,?\s*)+)/)
          next unless RailsCallbackChain.applies_to_action?(line, action)
          m[2].scan(/:(\w+[!?]?)/) do |name|
            callback = name[1]
            if m[1]?
              active.delete(callback)
            elsif !active.includes?(callback)
              active << callback
            end
          end
        end
      end
      # After its concerns, so the reversed list puts a class before them.
      paths << klass.path
    end
  end
end
