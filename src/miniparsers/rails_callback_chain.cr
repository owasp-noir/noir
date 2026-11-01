require "./ruby_constant_list"
require "./extraction_result_cache"
require "../ext/tree_sitter/tree_sitter"

module Noir
  # The `before_action` chain a Rails action runs. A controller's own class
  # body is only half of it: `before_action :authenticate_user!` usually sits
  # in ApplicationController, and `rails generate authentication` (Rails 8)
  # installs `before_action :require_authentication` through an
  # `Authentication` concern ApplicationController includes. Shared by the
  # Rails analyzer (header/cookie reads in callbacks) and the auth tagger
  # (whether a callback guards the action).
  class RailsCallbackChain
    # A Ruby class or module under a `controllers` directory, with its
    # class-body statements, each in the canonical text `Reader` writes.
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

    # The methods a `before_action` statement runs. The AST reader writes a
    # block callback as the one method it runs (see `Reader#block_callback`),
    # so the statement only ever names symbols.
    def self.before_action_callbacks(line : String) : Array(String)
      if m = line.match(SYMBOL_CALLBACKS)
        m[1].scan(/:(\w+[!?]?)/).map(&.[1])
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

    # Resolves `Const.method` to the literal list the app defines it as
    # (`Discourse.filters`); set by `build` over the files it was given.
    property list_resolver : Proc(String, Noir::RubyConstantList::Result?)? = nil

    # The `lifted` text of a callback whose `except:` splats something this
    # reader cannot expand: the guard stays, with a note.
    MAYBE_EXCEPTED = "except: with a splat it cannot read"

    # An `except:` that splats a method this reader cannot expand
    # (`*show_methods`) may well list the action.
    def self.maybe_excepted?(line : String, action : String?) : Bool
      return false unless (m = line.match(EXCEPT_OPTION)) && line[m.end..].matches?(/\*\w/)
      !(action && (callback_option(line, EXCEPT_OPTION) || [] of String).includes?(action))
    end

    # What the AST reader takes from one file: its classes and modules (by
    # the row they open on), its `def`s, its class macros, the canonical
    # text of each class-body statement by its first row, and the rows that
    # open a `class`. Shared by every chain built over the same source.
    record Facts, classes : Array({Int32, Klass}), defs : Array({String, Int32}),
      macros : Array({String, ClassMacro}), statements : Hash(Int32, String), class_rows : Set(Int32)

    @@facts = Hash(UInt64, Facts?).new
    @@facts_mutex = Mutex.new
    Noir::ExtractionResultCache.register_clearer { @@facts_mutex.synchronize { @@facts.clear } }

    # The file's `Facts`, read once per source; nil when it does not parse.
    def facts_for(path : String, source : String) : Facts?
      key = Noir::ExtractionResultCache.key(source, "rails_callback_chain", path)
      Noir::ExtractionResultCache.fetch(@@facts, key, @@facts_mutex) do
        Noir::TreeSitter.parse_ruby(source) { |root| Reader.new(path, source, @list_resolver).read(root) }
      rescue
        nil
      end
    end

    # Indexes every class and module `source` declares, with its class-body
    # callback statements.
    def add_file(path : String, source : String)
      return unless facts = facts_for(path, source)
      facts.classes.each do |row, klass|
        @classes[{path, row}] = klass
        (@by_name[klass.name] ||= [] of Klass) << klass
        (@by_path[path] ||= [] of Klass) << klass
      end
      facts.defs.each { |name, row| (@defs[name] ||= [] of {String, Int32}) << {path, row} }
      facts.macros.each { |name, class_macro| (@macros[name] ||= [] of ClassMacro) << class_macro }
    end

    # A chain over the `controllers` files, plus the `lib/` modules they (and
    # the modules those pull in) include: a controller's concern kept outside
    # `app/controllers`. `others` are the rest of the scan's Ruby files.
    def self.build(controllers : Enumerable(String), others : Enumerable(String), &block : String -> String?) : RailsCallbackChain
      chain = new
      cache = Hash(String, Noir::RubyConstantList::Result?).new
      all_files = controllers.to_a + others.to_a
      chain.list_resolver = ->(receiver : String) do
        cache.put_if_absent(receiver) do
          Noir::RubyConstantList.resolve(receiver, all_files) { |file| block.call(file) }
        end
      end
      controllers.each { |path| block.call(path).try { |source| chain.add_file(path, source) } }
      added = Set(String).new
      4.times do
        suffixes = chain.missing_include_paths.map { |lib_path| "/#{lib_path}" }
        break if suffixes.empty?
        by_base = suffixes.group_by { |suffix| File.basename(suffix) }
        found = others.select { |path| !added.includes?(path) && by_base[File.basename(path)]?.try(&.any? { |suffix| path.ends_with?(suffix) }) }
        break if found.empty?
        found.each do |path|
          added << path
          block.call(path).try { |source| chain.add_file(path, source) }
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
        elsif line.starts_with?("skip_before_action")
          # `skip_authentication only: [...]` is an app macro, read below.
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
          if depth == 0 && RailsCallbackChain.applies_to_action?(line, action)
            resolution.settings << macro_name
            resolution.lifted["macro:#{macro_name}"] = MAYBE_EXCEPTED if RailsCallbackChain.maybe_excepted?(line, action)
          end
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
            resolution.lifted[callback] = MAYBE_EXCEPTED if RailsCallbackChain.maybe_excepted?(line, action)
            active << callback unless active.includes?(callback)
          end
        end
      end
    end

    # Reads one parsed file into `Facts`. Every class-body call is written
    # out as the canonical statement the policies above parse:
    # `before_action :a, only: [:x, :y]` whatever the source spelled —
    # `:only => %i[x y]`, `only: ACTIONS` with `ACTIONS` assigned in the
    # class, a statement spread over lines, `before_filter`,
    # `send(:before_action, ...)`, or `before_action { a! }` (the one method
    # its block runs). Comments, strings and heredocs are not code to it.
    private class Reader
      alias Node = LibTreeSitter::TSNode

      # Callback macros by their spelling, mapped to the one the policies read.
      CALLBACK_NAMES = {
        "before_action" => "before_action", "prepend_before_action" => "prepend_before_action",
        "append_before_action" => "before_action", "skip_before_action" => "skip_before_action",
        "before_filter" => "before_action", "prepend_before_filter" => "prepend_before_action",
        "append_before_filter" => "before_action", "skip_before_filter" => "skip_before_action",
      }
      # `only:` / `except:`: the options naming actions.
      ACTION_OPTIONS = Set{"only", "except"}
      # Constructs a class body runs straight through, as statements of the class.
      PASS_THROUGH = Set{"body_statement", "block_body", "do_block", "block", "then", "else", "elsif",
                         "if", "unless", "case", "when", "in_clause", "begin", "ensure", "rescue",
                         "parenthesized_statements", "argument_list"}
      SPACES      = /\s+/
      ACTION_WORD = /\A[A-Za-z_]\w*[?!]?\z/
      PARENT_NAME = /\A(?:::)?[A-Z][\w:]*/

      @classes = [] of {Int32, Klass}
      @defs = [] of {String, Int32}
      @macros = [] of {String, ClassMacro}
      @statements = Hash(Int32, String).new
      @class_rows = Set(Int32).new
      # `NAME = value` in a class or module body, by `Scope::NAME`.
      @constants = Hash(String, Node).new
      # The one-expression body of each `def self.name` of the file.
      @class_methods = Hash(String, Node).new

      def initialize(@path : String, @source : String, @resolver : Proc(String, Noir::RubyConstantList::Result?)?)
      end

      def read(root : Node) : Facts
        index(root, "")
        body(root, nil, "", false)
        Facts.new(@classes, @defs, @macros, @statements, @class_rows)
      end

      private def type(node : Node) : String
        Noir::TreeSitter.node_type(node)
      end

      private def text(node : Node) : String
        Noir::TreeSitter.node_text(node, @source)
      end

      private def flat(node : Node) : String
        text(node).gsub(SPACES, " ").strip
      end

      private def field(node : Node, name : String) : Node?
        Noir::TreeSitter.field(node, name)
      end

      private def children(node : Node) : Array(Node)
        list = [] of Node
        Noir::TreeSitter.each_named_arg(node) { |child| list << child }
        list
      end

      # The constants and `def self.x` bodies the statements may name.
      private def index(node : Node, scope : String)
        Noir::TreeSitter.each_named_child(node) do |child|
          case type(child)
          when "class", "module"
            name = field(child, "name").try { |n| text(n) } || next
            inner = scope.empty? ? name : "#{scope}::#{name}"
            field(child, "body").try { |b| index(b, inner) }
          when "assignment"
            left = field(child, "left")
            right = field(child, "right")
            @constants["#{scope}::#{text(left)}"] = right if left && right && type(left) == "constant"
          when "singleton_method"
            if (name = field(child, "name")) && (only = single_statement(child))
              @class_methods[text(name)] = only
            end
          when "method", "lambda"
          else
            index(child, scope)
          end
        end
      end

      # A `def`'s only statement, through `@x ||= ...`.
      private def single_statement(method : Node) : Node?
        return unless body = field(method, "body")
        list = type(body) == "body_statement" ? children(body) : [body]
        return unless list.size == 1
        only = list.first
        type(only).in?("operator_assignment", "assignment") ? field(only, "right") : only
      end

      # The class-body statements under `node`. `singleton` is a
      # `class << self` / `class_methods do` body, whose `def`s are macros.
      private def body(node : Node, klass : Klass?, namespace : String, singleton : Bool)
        Noir::TreeSitter.each_named_child(node) do |child|
          case type(child)
          when "class", "module"
            open_class(child, namespace)
          when "method"
            add_def(child, klass, singleton)
          when "singleton_method"
            add_def(child, klass, field(child, "object").try { |o| type(o) == "self" } || false)
          when "singleton_class"
            field(child, "body").try { |b| body(b, klass, namespace, true) }
          when "call"
            class_call(child, klass, namespace, singleton)
          when "identifier"
            add_statement(child, flat(child), klass) if klass && !singleton
          when "if_modifier", "unless_modifier", "rescue_modifier", "while_modifier", "until_modifier"
            # Read as the class body has always been read: a modifier does not
            # make a class-body callback conditional.
            field(child, "body").try { |b| body_one(b, klass, namespace, singleton) }
          else
            body(child, klass, namespace, singleton) if PASS_THROUGH.includes?(type(child))
          end
        end
      end

      private def body_one(node : Node, klass : Klass?, namespace : String, singleton : Bool)
        case type(node)
        when "call"       then class_call(node, klass, namespace, singleton)
        when "identifier" then add_statement(node, flat(node), klass) if klass && !singleton
        else                   body(node, klass, namespace, singleton)
        end
      end

      private def open_class(node : Node, namespace : String)
        return unless name_node = field(node, "name")
        name = text(name_node)
        full = namespace.empty? ? name : "#{namespace}::#{name}"
        parent = field(node, "superclass").try { |sup| Noir::TreeSitter.first_named_child(sup) }.try { |p| text(p)[PARENT_NAME]? }
        row = Noir::TreeSitter.node_start_row(node)
        klass = Klass.new(full, namespace, parent, @path)
        @classes << {row, klass}
        @class_rows << row if type(node) == "class"
        field(node, "body").try { |b| body(b, klass, full, false) }
      end

      private def add_def(node : Node, klass : Klass?, class_macro : Bool)
        return unless name_node = field(node, "name")
        name = text(name_node)
        start_row = Noir::TreeSitter.node_start_row(node)
        @defs << {name, start_row}
        # A one-line `def self.x; end` registers nothing.
        return unless class_macro && Noir::TreeSitter.node_end_row(node) > start_row
        param = first_param(node)
        lines = [] of String
        field(node, "body").try { |b| macro_lines(b, klass, nil, lines) }
        @macros << {name, ClassMacro.new(@path, param.try { |p| /\s*,\s*\*{0,2}#{p}\b/ },
          param.try { |p| /(?<![\w@:])\*{0,2}#{p}\b/ }, lines)}
      end

      # The name of a parenthesised first parameter: the one the call's
      # arguments go to.
      private def first_param(node : Node) : String?
        return unless (params = field(node, "parameters")) && text(params).starts_with?('(')
        return unless first = children(params).first?
        return text(first) if type(first) == "identifier"
        return unless type(first).in?("optional_parameter", "keyword_parameter", "splat_parameter", "hash_splat_parameter")
        field(first, "name").try { |n| text(n) }
      end

      # The callback statements a macro body registers, each with the `if:`
      # / `unless:` the `if` / `unless` / `case` around it (or, failing one,
      # its own modifier) runs it on.
      private def macro_lines(node : Node, klass : Klass?, condition : String?, lines : Array(String))
        case type(node)
        when "call"
          if (statement = callback_statement(node, klass)) && statement.matches?(CALLBACK_LINE)
            lines << (condition ? "#{statement}, #{condition}" : statement)
            return
          end
        when "if", "unless"
          inner = field(node, "condition").try { |c| "#{type(node)}: -> { #{flat(c)} }" }
          Noir::TreeSitter.each_named_child(node) { |child| macro_lines(child, klass, inner || condition, lines) }
          return
        when "case"
          inner = field(node, "value").try { |c| "if: -> { #{flat(c)} }" }
          Noir::TreeSitter.each_named_child(node) { |child| macro_lines(child, klass, inner || condition, lines) }
          return
        when "if_modifier", "unless_modifier"
          modifier = field(node, "condition").try { |c| "#{type(node).rchop("_modifier")}: -> { #{flat(c)} }" }
          field(node, "body").try { |b| macro_lines(b, klass, condition || modifier, lines) }
          return
        when "method", "singleton_method", "class", "module"
          return
        end
        Noir::TreeSitter.each_named_child(node) { |child| macro_lines(child, klass, condition, lines) }
      end

      private def class_call(node : Node, klass : Klass?, namespace : String, singleton : Bool)
        receiver = field(node, "receiver")
        method = field(node, "method").try { |m| text(m) }
        if receiver.nil? && method == "class_methods" && (block = field(node, "block"))
          body(block, klass, namespace, true)
          return
        end
        # `private def x`, `helper_method def y`: the `def` is the argument.
        defs = field(node, "arguments").try { |list| children(list).select { |arg| type(arg).in?("method", "singleton_method") } }
        if defs && !defs.empty?
          defs.each { |m| add_def(m, klass, singleton || (type(m) == "singleton_method" && field(m, "object").try { |o| type(o) == "self" } || false)) }
          return
        end
        if klass && !singleton && (receiver.nil? || type(receiver) == "self") && (statement = callback_statement(node, klass))
          add_statement(node, statement, klass)
          return unless method && method.in?("included", "prepended", "concerning", "with_options", "class_eval", "instance_eval")
        end
        # `included do ... end`, `ActiveSupport.on_load(:x) do ... end`.
        field(node, "block").try { |inner| body(inner, klass, namespace, singleton) }
      end

      private def add_statement(node : Node, statement : String, klass : Klass)
        @statements[Noir::TreeSitter.node_start_row(node)] = statement
        klass.callbacks << statement
      end

      # `name args` for a receiver-less class-body call, in the canonical
      # spelling; nil for one the chain has no use for.
      private def callback_statement(node : Node, klass : Klass?) : String?
        return unless method_node = field(node, "method")
        name = text(method_node)
        return unless name.matches?(/\A[a-z_]\w*[!?]?\z/)
        args = field(node, "arguments").try { |list| children(list) } || [] of Node
        if name.in?("send", "public_send", "__send__") && (first = args.first?) && type(first) == "simple_symbol"
          name = text(first).lchop(':')
          args = args[1..]
        end
        name = CALLBACK_NAMES[name]? || name
        parts = [] of String
        if name.in?("before_action", "prepend_before_action")
          callable = args.find { |arg| type(arg) == "lambda" || lambda_call?(arg) } || field(node, "block")
          if callable
            args = args.reject { |arg| arg.id == callable.id }
            block_callback(callable).try { |callee| parts << ":#{callee}" }
          end
        end
        args.each { |arg| parts << argument(arg, klass) }
        parts.empty? ? name : "#{name} #{parts.join(", ")}"
      end

      # `lambda { ... }` / `proc { ... }` / `Proc.new { ... }`.
      private def lambda_call?(node : Node) : Bool
        return false unless type(node) == "call" && field(node, "block")
        method = field(node, "method").try { |m| text(m) }
        receiver = field(node, "receiver")
        (receiver.nil? && method.in?("lambda", "proc")) || (method == "new" && receiver.try { |r| text(r) } == "Proc")
      end

      # The one method a block callback runs unconditionally: its only
      # statement's, or the left operand's of a leading `&&` / `||`. A block
      # under `if` / `unless`, a call on a receiver (`->(c) {
      # c.authenticate! }`) or more than one statement yields none.
      private def block_callback(node : Node) : String?
        block = case type(node)
                when "lambda" then field(node, "body")
                when "call"   then field(node, "block")
                else               node
                end
        return unless block
        inner = children(block).reject { |child| type(child).in?("block_parameters", "lambda_parameters") }
        inner = children(inner.first) if inner.size == 1 && type(inner.first).in?("block_body", "body_statement")
        return unless inner.size == 1
        leading_call(inner.first)
      end

      private def leading_call(node : Node) : String?
        case type(node)
        when "binary"
          operator = field(node, "operator").try { |op| text(op) }
          return unless operator.in?("&&", "||", "and", "or")
          field(node, "left").try { |left| leading_call(left) }
        when "call"
          return if field(node, "receiver")
          field(node, "method").try { |m| text(m) }
        when "identifier"
          text(node)
        end
      end

      private def argument(node : Node, klass : Klass?) : String
        return flat(node) unless type(node) == "pair"
        key = field(node, "key")
        value = field(node, "value")
        return flat(node) unless key && value
        key_text = case type(key)
                   when "hash_key_symbol" then text(key)
                   when "simple_symbol"   then text(key).lchop(':')
                   when "string"          then string_value(key) || flat(key)
                   else                        flat(key)
                   end
        value_text = ACTION_OPTIONS.includes?(key_text) ? actions(value, klass) : flat(value)
        "#{key_text}: #{value_text}"
      end

      # An `only:` / `except:` value as `[:a, :b]` when its names can be
      # read, an array of what could be read otherwise, or the source text
      # (`only: PROTECTED`, which the policies treat as unreadable).
      private def actions(value : Node, klass : Klass?) : String
        value = unwrap_list(value)
        if names = names_of(value, klass, 0)
          return "[#{names.join(", ") { |n| ":#{n}" }}]"
        end
        return flat(value) unless type(value) == "array"
        "[#{children(value).join(", ") { |el| names_of(el, klass, 0).try(&.join(", ") { |n| ":#{n}" }) || flat(el) }}]"
      end

      # Calls that leave a list's names as they are: `%i[a b].freeze`, `[...].flatten`.
      LIST_PASS = Set{"freeze", "dup", "to_a", "flatten", "uniq", "compact"}

      # A call with neither arguments nor a block: `x.freeze`, `Discourse.filters`.
      private def plain_call?(node : Node) : Bool
        type(node) == "call" && field(node, "arguments").nil? && field(node, "block").nil?
      end

      private def unwrap_list(node : Node) : Node
        8.times do
          break unless plain_call?(node) && LIST_PASS.includes?(field(node, "method").try { |m| text(m) } || "")
          node = field(node, "receiver") || break
        end
        node
      end

      # The action names `node` stands for, or nil when any part of it
      # cannot be read.
      private def names_of(node : Node, klass : Klass?, depth : Int32) : Array(String)?
        return if depth > 8
        case type(node)
        when "simple_symbol"
          [text(node).lchop(':')]
        when "delimited_symbol", "string"
          string_value(node).try { |v| v.matches?(ACTION_WORD) ? [v] : nil }
        when "symbol_array", "string_array"
          children(node).map { |el| text(el) }
        when "array"
          names = [] of String
          children(node).each { |el| names.concat(names_of(el, klass, depth + 1) || return) }
          names
        when "splat_argument"
          Noir::TreeSitter.first_named_child(node).try { |inner| names_of(inner, klass, depth + 1) }
        when "parenthesized_statements"
          list = children(node)
          list.size == 1 ? names_of(list.first, klass, depth + 1) : nil
        when "binary"
          return unless field(node, "operator").try { |op| text(op) } == "+"
          left = field(node, "left").try { |l| names_of(l, klass, depth + 1) } || return
          right = field(node, "right").try { |r| names_of(r, klass, depth + 1) } || return
          left + right
        when "constant"
          constant(text(node), klass).try { |value| names_of(value, klass, depth + 1) }
        when "identifier"
          @class_methods[text(node)]?.try { |value| names_of(value, klass, depth + 1) }
        when "call"
          call_names(node, klass, depth)
        end
      end

      # `LIST.freeze`, `Discourse.filters` (a list another file defines, see
      # `RubyConstantList`), and `Discourse.filters.map { |f| "#{f}_feed" }`.
      private def call_names(node : Node, klass : Klass?, depth : Int32) : Array(String)?
        method = field(node, "method").try { |m| text(m) } || return
        receiver = field(node, "receiver") || return
        block = field(node, "block")
        if method == "map" && block && field(node, "arguments").nil?
          return map_names(receiver, block, klass, depth)
        end
        return unless plain_call?(node)
        return names_of(receiver, klass, depth + 1) if LIST_PASS.includes?(method)
        return unless type(receiver).in?("constant", "scope_resolution")
        @resolver.try(&.call("#{text(receiver)}.#{method}")).try(&.values)
      end

      private def map_names(receiver : Node, block : Node, klass : Klass?, depth : Int32) : Array(String)?
        values = names_of(receiver, klass, depth + 1) || return
        params = field(block, "parameters").try { |p| children(p) } || return
        return unless params.size == 1 && type(params.first) == "identifier"
        param = text(params.first)
        list = children(block).reject { |child| type(child) == "block_parameters" }
        list = children(list.first) if list.size == 1 && type(list.first).in?("block_body", "body_statement")
        return unless list.size == 1 && (template = list.first) && type(template).in?("string", "simple_symbol", "delimited_symbol")
        values.map do |value|
          String.build do |io|
            children(template).each do |part|
              case type(part)
              when "string_content"
                io << text(part)
              when "interpolation"
                inner = children(part)
                return unless inner.size == 1 && text(inner.first) == param
                io << value
              else
                return
              end
            end
          end
        end
      end

      # A constant the class or an enclosing scope of this file assigns.
      private def constant(name : String, klass : Klass?) : Node?
        scopes = (klass.try(&.name) || "").split("::", remove_empty: true)
        scopes.size.downto(0) do |n|
          if value = @constants["#{scopes[0, n].join("::")}::#{name}"]?
            return value
          end
        end
        nil
      end

      # The text of a literal with no interpolation.
      private def string_value(node : Node) : String?
        parts = children(node)
        return "" if parts.empty?
        return unless parts.size == 1 && type(parts.first) == "string_content"
        text(parts.first)
      end
    end
  end
end
