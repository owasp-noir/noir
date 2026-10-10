require "../../engines/php_engine"
require "../../../miniparsers/php_class_members"

module Analyzer::Php
  # Livewire components are reached through one endpoint, `POST
  # /livewire/update` (v3; v2 posts to `/livewire/message/<name>`), whose JSON payload names the component, the
  # property `updates` and the method `calls`. Every public method that is
  # not a lifecycle hook is a callable action and every public property is
  # client-writable unless `#[Locked]` / `#[Reactive]`.
  #
  # One endpoint per action, disambiguated by a URL fragment
  # (`/livewire/update#edit-post.save`) the way OpenRPC and GraphQL do it —
  # the optimizer dedupes on `(method, url)`, so without the fragment every
  # component would collapse into one endpoint. A component with no actions
  # still gets `#<component>` for its writable properties.
  #
  # Components: classes extending `Livewire\Component` (named from their
  # namespace below `…\Livewire\`, kebab-cased: `App\Livewire\Posts\EditPost`
  # → `posts.edit-post`) and class-based Volt single-file components
  # (`new class extends Component` in a Blade view, named from the view path).
  class Livewire < PhpEngine
    analyzer_for "php_livewire"

    DEFAULT_UPDATE_PATH = "/livewire/update"
    # Livewire 2 posts each component to its own `/livewire/message/<name>`.
    V2_MESSAGE_PATH = "/livewire/message/"
    V2_CONSTRAINT   = /"livewire\/livewire"\s*:\s*"[^"0-9]*2\./

    IMPORT_RE       = /Livewire\\(?:Volt\\)?Component\b/
    CLASS_RE        = /(?<!::)\b(abstract\s+)?(?:(?:final|readonly)\s+)*class\s+([A-Za-z_]\w*)\s+extends\s+\\?(?:Livewire\\(?:Volt\\)?)?Component\b[^{;]*\{/
    VOLT_RE         = /\bnew\s+class\b[^{;]*?\bextends\s+\\?(?:Livewire\\(?:Volt\\)?)?Component\b[^{;]*\{/
    NAMESPACE_RE    = /\bnamespace\s+([\w\\]+)\s*;/
    UPDATE_ROUTE_RE = /setUpdateRoute\s*\([^;]*?Route::post\s*\(\s*['"]([^'"]+)['"]/
    # Names Livewire refuses to call from the client: lifecycle hooks, their
    # per-trait variants (`mountWithTabs`) and the hydrate/update wildcards.
    LIFECYCLE_RE = /\A(?:render|placeholder|exception|rendering|rendered|(?:mount|boot|booted)(?:[A-Z]\w*)?|(?:hydrate|dehydrate|updating|updated)\w*|__\w+)\z/
    LOCKED_RE    = /#\[[^\]]*\b(?:Locked|Reactive)\b/
    COMPUTED_RE  = /#\[[^\]]*\bComputed\b/
    VIEW_DIRS    = ["views/livewire/", "views/"]

    # `setUpdateRoute` path per app (`composer_project_root`), so one app's
    # custom route does not move a sibling app's components.
    @update_paths = {} of String => String
    @update_path_lock = Mutex.new
    @v2_roots = {} of String => Bool
    # Project classes extending `Component` by short name, with their
    # writable props and actions, so `class UsersTable extends BaseTable`
    # is a component that inherits them.
    # ponytail: one level deep; a base of a base is not followed.
    alias Members = Tuple(Array(Param), Array(Noir::PhpClassMembers::Member))
    @bases = {} of String => Members
    @subclass_re : Regex? = nil

    def analyze
      ordered_file_scan do |path|
        content = read_file_content(path)
        next if path.ends_with?(".blade.php") || !content.matches?(IMPORT_RE)
        lexer = Noir::PhpLexer.new(content)
        masked = lexer.masked.join
        found = [] of Tuple(String, Members)
        masked.scan(CLASS_RE) { |m| members(lexer, masked, m).try { |members| found << {m[2], members} } }
        found
      end.each { |found| found.each { |name, members| @bases[name] = members } }
      unless @bases.empty?
        @subclass_re = /(?<!::)\b(abstract\s+)?(?:(?:final|readonly)\s+)*class\s+([A-Za-z_]\w*)\s+extends\s+\\?(?:[\w\\]+\\)?(#{@bases.keys.join('|')})\b[^{;]*\{/
      end

      super
      return result if @update_paths.empty?
      result.each_with_index do |endpoint, idx|
        file = endpoint.details.code_paths.first?.try(&.path) || next
        custom = @update_paths[composer_project_root(file)]? || next
        endpoint.url = endpoint.url.sub(DEFAULT_UPDATE_PATH, custom)
        result[idx] = endpoint
      end
      result
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = read_file_content(path)

      if content.includes?("setUpdateRoute") && (m = php_code(content).match(UPDATE_ROUTE_RE))
        root = composer_project_root(path)
        @update_path_lock.synchronize { @update_paths[root] = "/" + m[1].lstrip('/') }
      end
      imports = content.matches?(IMPORT_RE)
      subclass_re = @subclass_re if content.includes?("extends")
      return endpoints unless imports || subclass_re

      lexer = Noir::PhpLexer.new(content)
      masked = lexer.masked.join
      if path.ends_with?(".blade.php")
        if imports && (m = VOLT_RE.match(masked)) && (name = volt_name(path))
          emit(endpoints, lexer, masked, m, name, path)
        end
      else
        prefix = component_prefix(masked)
        {imports ? CLASS_RE : nil, subclass_re}.each do |class_re|
          next unless class_re
          masked.scan(class_re) do |decl|
            # Abstract base components are never mounted.
            emit(endpoints, lexer, masked, decl, prefix + kebab(decl[2]), path, decl[3]?.try { |base| @bases[base]? }) unless decl[1]?
          end
        end
      end
      endpoints
    rescue e
      logger.debug "Error analyzing Livewire component #{path}: #{e}"
      Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      [] of Endpoint
    end

    private def members(lexer : Noir::PhpLexer, masked : String, decl : Regex::MatchData) : Members?
      open = decl.end(0) - 1
      close = lexer.matching_delimiter(open)
      return unless close

      props = [] of Param
      actions = [] of Noir::PhpClassMembers::Member
      Noir::PhpClassMembers.each(lexer, masked, open, close) do |member|
        next if member.static
        if member.method
          actions << member unless member.name.matches?(LIFECYCLE_RE) || member.prelude.matches?(COMPUTED_RE)
        elsif !member.readonly && !member.prelude.matches?(LOCKED_RE)
          props << Param.new(member.name, "", "json")
        end
      end
      {props, actions}
    end

    private def emit(endpoints : Array(Endpoint), lexer : Noir::PhpLexer, masked : String,
                     decl : Regex::MatchData, name : String, path : String, inherited : Members? = nil)
      props, actions = members(lexer, masked, decl) || return
      own_actions = actions.size
      if inherited
        inherited[0].each { |prop| props << prop unless props.any? { |p| p.name == prop.name } }
        inherited[1].each { |action| actions << action unless actions.any? { |a| a.name == action.name } }
      end
      decl_line = line_number_for_index(masked, decl.begin(0))

      v2 = livewire_v2?(path)
      if actions.empty?
        return if props.empty?
        url = v2 ? "#{V2_MESSAGE_PATH}#{name}" : "#{DEFAULT_UPDATE_PATH}##{name}"
        endpoints << Endpoint.new(url, "POST", props,
          Details.new(PathInfo.new(path, decl_line)))
        return
      end

      actions.each_with_index do |action, idx|
        params = props.dup
        action.args.each { |arg| params << Param.new(arg, "", "json") unless params.any? { |p| p.name == arg } }
        url = v2 ? "#{V2_MESSAGE_PATH}#{name}##{action.name}" : "#{DEFAULT_UPDATE_PATH}##{name}.#{action.name}"
        endpoints << Endpoint.new(url, "POST", params,
          # An inherited action is reported at the subclass declaration.
          Details.new(PathInfo.new(path, idx < own_actions ? action.line : decl_line)))
      end
    end

    private def livewire_v2?(path : String) : Bool
      root = composer_project_root(path)
      return false if root.empty?
      @update_path_lock.synchronize do
        @v2_roots.fetch(root) do
          @v2_roots[root] = (read_file_content(File.join(root, "composer.json")).matches?(V2_CONSTRAINT) rescue false)
        end
      end
    end

    # `App\Livewire\Posts` → `posts.` — the namespace below the last
    # `Livewire` segment, which is how Livewire names discovered classes.
    private def component_prefix(masked : String) : String
      ns = masked.match(NAMESPACE_RE).try(&.[1]) || return ""
      segments = ns.split('\\')
      idx = segments.rindex("Livewire") || return ""
      segments[(idx + 1)..].map { |seg| kebab(seg) + "." }.join
    end

    # `resources/views/livewire/posts/edit.blade.php` → `posts.edit`.
    private def volt_name(path : String) : String?
      rel = base_relative_path(path)
      VIEW_DIRS.each do |dir|
        if idx = rel.index(dir)
          return rel[(idx + dir.size)..].rchop(".blade.php").gsub('/', '.')
        end
      end
      nil
    end

    # Laravel's `Str::kebab`: a dash before every capital that follows a
    # character, then lowercase (`EditPost` → `edit-post`).
    private def kebab(name : String) : String
      name.gsub(/(.)(?=[A-Z])/, "\\1-").downcase
    end
  end
end
