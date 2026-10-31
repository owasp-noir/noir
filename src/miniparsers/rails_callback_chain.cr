require "./ruby_constant_list"

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
    # under an `if:` condition (see `conditional?`), and the active callbacks
    # a `skip_before_action ..., if:` / `unless:` lifts on a condition, with
    # that condition's text, and the CanCanCan `authorize_resource` /
    # `load_and_authorize_resource` statements left active for the action,
    # and the class macros (`requires_login`) the class's own body calls for
    # the action, which may set what a callback reads off `self.class`.
    record Resolution, callbacks : Array(String), paths : Array(String), conditional : Set(String),
      lifted : Hash(String, String) = Hash(String, String).new, cancan : Array(String) = [] of String,
      settings : Set(String) = Set(String).new

    # Class-body lines that change the callback chain a subclass inherits.
    CALLBACK_LINE = /^(?:include|(?:prepend_|skip_)?before_action|allow_unauthenticated_access|(?:skip_)?(?:load_and_)?authorize_resource)\b/

    # Gem controllers an app subclasses, which are not in the scan: the
    # callback lines their class bodies register. Doorkeeper's
    # `authenticate_resource_owner!` / `authenticate_admin!` run the app's
    # `resource_owner_authenticator` / `admin_authenticator` blocks.
    GEM_CALLBACKS = {
      "Doorkeeper::AuthorizationsController"         => ["before_action :authenticate_resource_owner!"],
      "Doorkeeper::AuthorizedApplicationsController" => ["before_action :authenticate_resource_owner!"],
      "Doorkeeper::ApplicationsController"           => ["before_action :authenticate_admin!"],
    }

    # CanCanCan's class macros, which register a `before_action` that runs
    # `authorize!(action, resource)`.
    CANCAN_LINE = /\A(?:skip_)?(?:load_and_)?authorize_resource\b/

    # `only: [...]` or the hash-rocket `:only => [...]` older apps write.
    ONLY_OPTION   = /\bonly:|:only\s*=>/
    EXCEPT_OPTION = /\bexcept:|:except\s*=>/

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
      line.matches?(/\bif:|:if\s*=>/)
    end

    getter classes = Hash({String, Int32}, Klass).new
    getter defs = Hash(String, Array({String, Int32})).new
    # A `def self.requires_login(arg = {})` body: the file defining it, the
    # patterns that drop or bind the parameter the call's arguments go to,
    # and the callback lines the body registers (`before_action
    # :ensure_logged_in, arg`).
    record ClassMacro, path : String, drop : Regex?, bind : Regex?, body : Array(String)
    getter macros = Hash(String, Array(ClassMacro)).new
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
      while (text.ends_with?(',') || open_brackets?(text)) && j < lines.size && j - idx <= 80
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

    # An `only:` / `except:` naming its actions through a constant or a
    # method (`only: PROTECTED`) lists actions this reader cannot see: a
    # callback is taken to run for every action and a skip for none, which
    # keeps the guard.
    def self.applies_to_action?(line : String, action : String?) : Bool
      if opaque_option?(line)
        return !line.matches?(/\A(?:skip_|allow_unauthenticated_access\b)/)
      end
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
      if stop = value.index(/\b\w+:(?!:)|:\w+\s*=>/)
        value = value[0, stop]
      end
      value.gsub(/%[iwIW][\[(]/, " ").scan(/\w+[?!]?/).map(&.[0])
    end

    def self.opaque_option?(line : String) : Bool
      {ONLY_OPTION, EXCEPT_OPTION}.any? do |option|
        (m = line.match(option)) && line[m.end..].matches?(/\A\s*[A-Za-z_@]/)
      end
    end

    # Indexes every class and module `lines` declares, with its class-body
    # callback lines. Lines inside a `def` are not class-body: the
    # `Authentication` concern's own `def allow_unauthenticated_access` wraps
    # a `skip_before_action` that runs only when a controller calls it.
    # Resolves `Const.method` to the literal list the app defines it as
    # (`Discourse.filters`); set by `build` over the files it was given.
    property list_resolver : Proc(String, Noir::RubyConstantList::Result?)? = nil

    LIST_TERM = /((?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\.[a-z_]\w*)(?:\.map\s*\{\s*\|(\w+)\|\s*:?"([^"]*)"\s*\})?/

    # Names in an `only:` / `except:` list that a constant spells out
    # (`except: [:top, Discourse.anonymous_filters, Discourse.filters.map {
    # |f| "#{f}_feed" }]`) written as the symbols they stand for, so the
    # list can be read as a list. A term that does not resolve stays as is.
    private def expand_lists(text : String) : String
      return text unless (resolver = @list_resolver) && (text.includes?("only:") || text.includes?("except:"))
      text.gsub(LIST_TERM) do |term, match|
        next term unless list = resolver.call(match[1])
        names = if template = match[3]?
                  list.values.map { |value| template.gsub(/\#\{\s*#{Regex.escape(match[2])}\s*\}/, value) }
                else
                  list.values
                end
        names.join(", ") { |name| ":#{name}" }
      end
    end

    def add_file(path : String, lines : Array(String))
      stack = [] of {Klass, Int32}
      def_indent : Int32? = nil
      macro_body : Array(String)? = nil
      lines.each_with_index do |line, idx|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')
        indent = line.size - line.lstrip.size
        if open_def = def_indent
          if indent <= open_def && stripped == "end"
            def_indent = nil
          elsif (body = macro_body) && stripped.matches?(CALLBACK_LINE)
            body << expand_lists(RailsCallbackChain.statement(lines, idx))
          end
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
        elsif m = stripped.match(/^def\s+(self\.)?(\w+[!?]?)/)
          (@defs[m[2]] ||= [] of {String, Int32}) << {path, idx}
          def_indent = indent unless stripped.matches?(/\bend$|^def\s+[\w.?!]+(?:\([^)]*\))?\s*=[^=]/)
          macro_body = nil
          if m[1]? && def_indent
            macro_body = [] of String
            param = stripped.match(/\A[^(]*\(\s*\*{0,2}(\w+)/).try(&.[1])
            (@macros[m[2]] ||= [] of ClassMacro) << ClassMacro.new(path, param.try { |name| /\s*,\s*\*{0,2}#{name}\b/ },
              param.try { |name| /(?<![\w@:])\*{0,2}#{name}\b/ }, macro_body)
          end
        elsif (top = stack.last?) && stripped.matches?(CALLBACK_LINE)
          top[0].callbacks << expand_lists(RailsCallbackChain.statement(lines, idx))
        elsif (top = stack.last?) && stripped.matches?(MACRO_CALL)
          # A class macro the app may define (`requires_login`): kept for
          # `apply_lines`, which expands it once every file is indexed.
          top[0].callbacks << expand_lists(RailsCallbackChain.statement(lines, idx))
        end
      end
    end

    # A class-body call with no receiver: `requires_login`, `requires_login only: [:x]`.
    MACRO_CALL = /\A[a-z_]\w*[!?]?(?:\s+[^=\s]|\(|\z)/

    # A chain over the `controllers` files, plus the `lib/` modules they (and
    # the modules those pull in) include: a controller's concern kept outside
    # `app/controllers`. `others` are the rest of the scan's Ruby files.
    def self.build(controllers : Enumerable(String), others : Enumerable(String), &block : String -> Array(String)?) : RailsCallbackChain
      chain = new
      cache = Hash(String, Noir::RubyConstantList::Result?).new
      all_files = controllers.to_a + others.to_a
      chain.list_resolver = ->(receiver : String) do
        cache.put_if_absent(receiver) do
          Noir::RubyConstantList.resolve(receiver, all_files) { |file| block.call(file).try(&.join("\n")) }
        end
      end
      controllers.each { |path| block.call(path).try { |lines| chain.add_file(path, lines) } }
      added = Set(String).new
      4.times do
        suffixes = chain.missing_include_paths.map { |lib_path| "/#{lib_path}" }
        break if suffixes.empty?
        by_base = suffixes.group_by { |suffix| File.basename(suffix) }
        found = others.select { |path| !added.includes?(path) && by_base[File.basename(path)]?.try(&.any? { |suffix| path.ends_with?(suffix) }) }
        break if found.empty?
        found.each do |path|
          added << path
          block.call(path).try { |lines| chain.add_file(path, lines) }
        end
      end
      chain
    end

    # The roots outside `app/controllers` that Rails autoloads the modules a
    # controller `include`s from (`lib/`, `app/helpers/`, ...).
    INCLUDE_ROOTS = %w[lib app/helpers app/models/concerns]

    # The paths Rails autoloads the modules indexed classes `include`
    # from, for each one no indexed file declares: `include UploadHelpers` in
    # `Admin::UploadsController` is `lib/admin/upload_helpers.rb` or
    # `lib/upload_helpers.rb`, nearest namespace first, as Zeitwerk looks.
    def missing_include_paths : Array(String)
      @classes.values.flat_map do |klass|
        scopes = klass.namespace.split("::", remove_empty: true)
        klass.callbacks.select(&.starts_with?("include")).flat_map do |line|
          line.scan(/[A-Z][\w:]*/).flat_map do |m|
            next [] of String if lookup(m[0], klass.namespace)
            name = m[0].lchop("::")
            (m[0].starts_with?("::") ? 0 : scopes.size).downto(0).flat_map do |n|
              INCLUDE_ROOTS.map { |root| "#{root}/#{(scopes[0, n] + [name]).join("::").underscore.gsub("::", "/")}.rb" }
            end
          end
        end
      end.uniq!
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
      apply_lines(klass.callbacks, klass.namespace, action, resolution, depth, klass.path)
      # After its concerns, so the reversed list puts a class before them.
      resolution.paths << klass.path
    end

    private def apply_lines(lines : Array(String), namespace : String, action : String?, resolution : Resolution, depth : Int32, own_path : String? = nil)
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
        elsif line.matches?(CANCAN_LINE)
          next unless RailsCallbackChain.applies_to_action?(line, action)
          # ponytail: a skip drops every macro, not only the named resource's.
          if line.starts_with?("skip_")
            resolution.cancan.clear
          elsif !RailsCallbackChain.conditional?(line) && !line.matches?(/(?:\bunless:|:unless\s*=>)/)
            resolution.cancan << line
          end
        elsif line.starts_with?("skip_")
          next unless RailsCallbackChain.applies_to_action?(line, action)
          next unless m = line.match(/^skip_before_action\s+((?::\w+[!?]?\s*,?\s*)+)/)
          # A skip on a condition leaves the callback registered: whether it
          # runs is that condition's to decide.
          lift = line.match(/(?:\b(?:if|unless):|:(?:if|unless)\s*=>)\s*(.+)\z/).try(&.[0])
          m[1].scan(/:(\w+[!?]?)/) do |name|
            if lift
              resolution.lifted[name[1]] = lift
            else
              active.delete(name[1])
              resolution.conditional.delete(name[1])
              resolution.lifted.delete(name[1])
            end
          end
        elsif !line.matches?(CALLBACK_LINE) && (macro_name = line[/\A[a-z_]\w*[!?]?/]?) && depth < 16 &&
              (class_macro = @macros[macro_name]?.try(&.find { |defined| defined.path == own_path || resolution.paths.includes?(defined.path) }))
          # A macro the class or one of its ancestors defines, its lines with
          # the parameter bound to the call's arguments: `requires_login
          # only: [:x]` registers `before_action :ensure_logged_in, only: [:x]`.
          # ponytail: a class instance variable is the routed class's own, so
          # only its body (depth 0) sets one; a `class_attribute` a parent
          # sets reads as unset.
          resolution.settings << macro_name if depth == 0 && RailsCallbackChain.applies_to_action?(line, action)
          args = line[macro_name.size..].strip.lchop('(').rchop(')').strip
          expanded = class_macro.body.map do |text|
            if args.empty?
              class_macro.drop.try { |drop| text.sub(drop, "") } || text
            else
              class_macro.bind.try { |bind| text.gsub(bind, args) } || text
            end
          end
          apply_lines(expanded, namespace, action, resolution, depth + 1, own_path)
        elsif RailsCallbackChain.applies_to_action?(line, action)
          RailsCallbackChain.before_action_callbacks(line).each do |callback|
            # Registering a callback again replaces its options.
            if RailsCallbackChain.conditional?(line)
              resolution.conditional << callback
            else
              resolution.conditional.delete(callback)
            end
            resolution.lifted.delete(callback)
            active << callback unless active.includes?(callback)
          end
        end
      end
    end
  end
end
