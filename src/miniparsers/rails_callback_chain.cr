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

    # The callbacks left active for an action, in registration order, the
    # files of the classes/modules it passed through, nearest first (where
    # Ruby looks a callback's `def` up), and the active callbacks registered
    # under an `if:` condition (see `conditional?`).
    record Resolution, callbacks : Array(String), paths : Array(String), conditional : Set(String)

    # Class-body lines that change the callback chain a subclass inherits.
    CALLBACK_LINE = /^(?:include|(?:prepend_|skip_)?before_action|allow_unauthenticated_access)\b/

    # Gem controllers an app subclasses, which are not in the scan: the
    # callback lines their class bodies register. Doorkeeper's
    # `authenticate_resource_owner!` / `authenticate_admin!` run the app's
    # `resource_owner_authenticator` / `admin_authenticator` blocks.
    GEM_CALLBACKS = {
      "Doorkeeper::AuthorizationsController"         => ["before_action :authenticate_resource_owner!"],
      "Doorkeeper::AuthorizedApplicationsController" => ["before_action :authenticate_resource_owner!"],
      "Doorkeeper::ApplicationsController"           => ["before_action :authenticate_admin!"],
    }

    ONLY_OPTION   = /\bonly:/
    EXCEPT_OPTION = /\bexcept:/

    # `before_action :a, :b` — the symbol callbacks it registers.
    SYMBOL_CALLBACKS = /(?<!skip_)before_action\s*\(?\s*((?::\w+[!?]?\s*,?\s*)+)/
    # `before_action -> { doorkeeper_authorize! :read }` (also `->(c) {`,
    # `lambda {`, `proc {`, a bare `{ ... }` block): the block body.
    BLOCK_CALLBACK = /(?<!skip_)before_action\s*\(?\s*(?:->\s*(?:\([^)]*\))?|lambda\s*|proc\s*)?\{(?:\s*\|[^|]*\|)?([^{}]*)\}/

    # The methods a `before_action` line runs: its symbol callbacks, or the
    # one method its block calls. A block body that is anything but a single
    # call (`-> { a! if b? }`, `-> { x? && y }`) runs nothing unconditionally
    # and yields none.
    def self.before_action_callbacks(line : String) : Array(String)
      if m = line.match(SYMBOL_CALLBACKS)
        m[1].scan(/:(\w+[!?]?)/).map(&.[1])
      elsif (m = line.match(BLOCK_CALLBACK)) && (call = m[1].match(/\A\s*([a-z_]\w*[!?]?)(?:[\s(][^;]*)?\z/)) &&
            !m[1].matches?(/\b(?:if|unless)\b|&&|\|\|/)
        [call[1]]
      else
        [] of String
      end
    end

    # `before_action :x, if: :cond?` runs `x` only when the condition holds,
    # so a request can skip it: an opt-in such as
    # `if: :limited_federation_mode?` leaves the action public by default.
    # `unless:` is read as an exemption, the way `except:` is —
    # `unless: :devise_controller?` guards every app controller.
    def self.conditional?(line : String) : Bool
      line.matches?(/\bif:/)
    end

    getter classes = Hash({String, Int32}, Klass).new
    getter defs = Hash(String, Array({String, Int32})).new
    @by_name = Hash(String, Array(Klass)).new
    @by_path = Hash(String, Array(Klass)).new

    # The statement starting at `lines[idx]`, joined across the lines a
    # trailing comma or an unclosed `[` / `(` / `{` continues it onto:
    # `before_action :x, # note` with its `only: [...]` on the next line,
    # or `only: [` closed lines later, applies to those actions only.
    # Trailing comments are dropped.
    # ponytail: a `#` inside a string on a callback line reads as a comment.
    def self.statement(lines : Array(String), idx : Int32) : String
      text = uncomment(lines[idx])
      j = idx + 1
      while (text.ends_with?(',') || open_brackets?(text)) && j < lines.size && j - idx <= 10
        text = "#{text} #{uncomment(lines[j])}"
        j += 1
      end
      text
    end

    private def self.uncomment(line : String) : String
      line.sub(/\s+#.*\z/, "").strip
    end

    private def self.open_brackets?(text : String) : Bool
      text.count("[({") > text.count("])}")
    end

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
          top[0].callbacks << RailsCallbackChain.statement(lines, idx)
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
    # monorepo) are ambiguous and resolve to nothing. `skip` is the class
    # whose superclass is being looked up: `module Admin; class
    # ApplicationController < ApplicationController` names the top-level one,
    # since the superclass is read before the new constant exists.
    def lookup(name : String, namespace : String, skip : Klass? = nil) : Klass?
      name = name.lchop("::")
      scopes = namespace.split("::", remove_empty: true)
      scopes.size.downto(0) do |n|
        full = (scopes[0, n] + [name]).join("::")
        if found = @by_name[full]?
          next if skip && found.all?(&.name.==(skip.name))
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
    # ends the chain, after its `GEM_CALLBACKS` when it has any.
    def resolve(leaf : Klass, action : String?) : Resolution
      resolution = Resolution.new(Array(String).new, Array(String).new, Set(String).new)
      apply_ancestor(leaf, action, resolution, 0)
      resolution.paths.reverse!.uniq!
      resolution
    end

    private def apply_ancestor(klass : Klass?, action : String?, resolution : Resolution, depth : Int32)
      return unless klass && depth < 16
      if parent = klass.parent
        if found = lookup(parent, klass.namespace, klass)
          apply_ancestor(found, action, resolution, depth + 1)
        elsif gem = GEM_CALLBACKS[parent.lchop("::")]?
          apply_lines(gem, "", action, resolution, depth + 1)
        end
      end
      apply_callbacks(klass, action, resolution, depth)
    end

    private def apply_callbacks(klass : Klass, action : String?, resolution : Resolution, depth : Int32)
      apply_lines(klass.callbacks, klass.namespace, action, resolution, depth)
      # After its concerns, so the reversed list puts a class before them.
      resolution.paths << klass.path
    end

    private def apply_lines(lines : Array(String), namespace : String, action : String?, resolution : Resolution, depth : Int32)
      active = resolution.callbacks
      lines.each do |line|
        if line.starts_with?("include")
          line.scan(/[A-Z][\w:]*/) do |m|
            if (mod = lookup(m[0], namespace)) && depth < 16
              apply_callbacks(mod, action, resolution, depth + 1)
            end
          end
        elsif line.starts_with?("allow_unauthenticated_access")
          active.delete("require_authentication") if RailsCallbackChain.applies_to_action?(line, action)
        elsif line.starts_with?("skip_")
          next unless RailsCallbackChain.applies_to_action?(line, action)
          next unless m = line.match(/^skip_before_action\s+((?::\w+[!?]?\s*,?\s*)+)/)
          m[1].scan(/:(\w+[!?]?)/) do |name|
            active.delete(name[1])
            resolution.conditional.delete(name[1])
          end
        elsif RailsCallbackChain.applies_to_action?(line, action)
          RailsCallbackChain.before_action_callbacks(line).each do |callback|
            # Registering a callback again replaces its options.
            if RailsCallbackChain.conditional?(line)
              resolution.conditional << callback
            else
              resolution.conditional.delete(callback)
            end
            active << callback unless active.includes?(callback)
          end
        end
      end
    end
  end
end
