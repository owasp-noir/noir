require "../../engines/php_engine"
require "../../../miniparsers/php_class_members"

module Analyzer::Php
  # Livewire components are reached through one endpoint, `POST
  # /livewire/update` (v3), whose JSON payload names the component, the
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

    def analyze
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
      return endpoints unless content.matches?(IMPORT_RE)

      lexer = Noir::PhpLexer.new(content)
      masked = lexer.masked.join
      if path.ends_with?(".blade.php")
        if (m = VOLT_RE.match(masked)) && (name = volt_name(path))
          emit(endpoints, lexer, masked, m, name, path)
        end
      else
        prefix = component_prefix(masked)
        pos = 0
        while m = CLASS_RE.match(masked, pos)
          # Abstract base components are never mounted.
          emit(endpoints, lexer, masked, m, prefix + kebab(m[2]), path) unless m[1]?
          pos = m.end(0)
        end
      end
      endpoints
    rescue e
      logger.debug "Error analyzing Livewire component #{path}: #{e}"
      Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      [] of Endpoint
    end

    private def emit(endpoints : Array(Endpoint), lexer : Noir::PhpLexer, masked : String,
                     decl : Regex::MatchData, name : String, path : String)
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

      if actions.empty?
        return if props.empty?
        endpoints << Endpoint.new("#{DEFAULT_UPDATE_PATH}##{name}", "POST", props,
          Details.new(PathInfo.new(path, line_number_for_index(masked, decl.begin(0)))))
        return
      end

      actions.each do |action|
        params = props.dup
        action.args.each { |arg| params << Param.new(arg, "", "json") unless params.any? { |p| p.name == arg } }
        endpoints << Endpoint.new("#{DEFAULT_UPDATE_PATH}##{name}.#{action.name}", "POST", params,
          Details.new(PathInfo.new(path, action.line)))
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
