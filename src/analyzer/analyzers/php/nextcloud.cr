require "../../engines/php_engine"
require "../../../miniparsers/php_class_members"

module Analyzer::Php
  # Nextcloud apps declare routes in `appinfo/routes.php`:
  #
  #     return [
  #         'routes'    => [['name' => 'note#update', 'url' => '/notes/{id}', 'verb' => 'PUT']],
  #         'ocs'       => [['name' => 'api#share', 'url' => '/api/v1/share', 'verb' => 'POST']],
  #         'resources' => ['note' => ['url' => '/notes']],
  #     ];
  #
  # or with `#[FrontpageRoute(verb:, url:)]` / `#[ApiRoute(verb:, url:)]` on
  # controller methods. Frontpage routes and resources are served under
  # `/apps/<id>`, OCS ones under `/ocs/v2.php/apps/<id>`; `<id>` comes from
  # `appinfo/info.xml`. `name` resolves to `lib/Controller/<Name>Controller`,
  # whose method arguments become params and whose `#[PublicPage]`,
  # `#[NoAdminRequired]`, `#[NoCSRFRequired]`, `#[AuthorizedAdminSetting]`
  # (or legacy `@PublicPage`-style docblock annotations) become tags.
  class Nextcloud < PhpEngine
    analyzer_for "php_nextcloud"

    TAGGER = "nextcloud_analyzer"
    OCS    = "/ocs/v2.php"
    # RouteParser honours a frontpage route's `root` only for these apps; OCS
    # routes may always set one.
    ROOT_URL_APPS = %w[cloud_federation_api core files files_sharing profile settings spreed]

    # group key => OCS?
    ROUTE_GROUPS    = {"routes" => false, "ocs" => true}
    RESOURCE_GROUPS = {"resources" => false, "ocs-resources" => true}
    # Nextcloud's RouteParser: {action, verb, on the member URL `/{id}`?}
    RESOURCE_ACTIONS = [
      {"index", "GET", false}, {"show", "GET", true}, {"create", "POST", false},
      {"update", "PUT", true}, {"destroy", "DELETE", true},
    ]

    APP_ID_RE     = /<id>\s*([^<\s]+)\s*<\/id>/
    NAMESPACE_RE  = /\bnamespace\s+OCA\\(\w+)/
    ENTRY_KEY_RE  = /['"](name|url|verb|root)['"]\s*=>\s*['"]([^'"]*)['"]/
    RESOURCE_KEY  = /['"]([^'"]+)['"]\s*=>\s*\z/
    ROUTE_ATTR_RE = /\b(FrontpageRoute|ApiRoute)\s*\(([^)]*)\)/
    NAMED_ARG_RE  = /\b(verb|url|root)\s*:\s*['"]([^'"]*)['"]/
    STRING_RE     = /'([^']*)'|"([^"]*)"/

    alias Methods = Hash(String, Noir::PhpClassMembers::Member)

    # app root directory => app id
    @apps = {} of String => String

    def analyze
      get_files_by_basename("info.xml").each do |info|
        appinfo = File.dirname(info)
        next unless File.basename(appinfo) == "appinfo"
        root = File.dirname(appinfo)
        @apps[root] = read_file_content(info).match(APP_ID_RE).try(&.[1]) || File.basename(root)
      end
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      app = @apps.select { |root, _| path.starts_with?(root + "/") }.max_by? { |root, _| root.size }
      # `appinfo/routes.php`, plus the files apps split it into and
      # `include` from it (Talk's `appinfo/routes/routesXController.php`).
      if app && (path == File.join(app[0], "appinfo", "routes.php") || path.starts_with?(File.join(app[0], "appinfo", "routes") + "/"))
        routes_file(endpoints, path, app[0], app[1])
      else
        content = read_file_content(path)
        return endpoints unless content.includes?("Route") && content.includes?("OCP\\AppFramework")
        id = app.try(&.[1]) || content.match(NAMESPACE_RE).try(&.[1].downcase)
        attribute_routes(endpoints, path, content, id) if id
      end
      endpoints
    rescue e
      logger.debug "Error analyzing Nextcloud routes #{path}: #{e}"
      Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      [] of Endpoint
    end

    private def routes_file(endpoints : Array(Endpoint), path : String, root : String, id : String)
      content = read_file_content(path)
      lexer = Noir::PhpLexer.new(content)
      controllers = {} of String => Methods

      ROUTE_GROUPS.each do |group, ocs|
        each_group_entry(content, lexer, group) do |entry_open, entry_close, _|
          fields = entry_fields(lexer.source(entry_open..entry_close))
          url = fields["url"]? || next
          controller, _, action = (fields["name"]? || "").partition('#')
          method = find_method(controllers, root, controller, action)
          details = Details.new(PathInfo.new(path, line_number_for_index(content, entry_open)))
          endpoints << endpoint(route_url(id, ocs, fields["root"]?, url), (fields["verb"]? || "GET").upcase, details, method)
        end
      end

      RESOURCE_GROUPS.each do |group, ocs|
        each_group_entry(content, lexer, group) do |entry_open, entry_close, resource|
          next unless resource
          fields = entry_fields(lexer.source(entry_open..entry_close))
          url = fields["url"]? || next
          base = route_url(id, ocs, fields["root"]?, url)
          line = line_number_for_index(content, entry_open)
          RESOURCE_ACTIONS.each do |action, verb, member|
            method = find_method(controllers, root, resource, action)
            details = Details.new(PathInfo.new(path, line))
            endpoints << endpoint(member ? "#{base.rstrip('/')}/{id}" : base, verb, details, method)
          end
        end
      end
    end

    private def attribute_routes(endpoints : Array(Endpoint), path : String, content : String, id : String)
      each_method(content) do |method|
        method.prelude.scan(ROUTE_ATTR_RE) do |attr|
          named = attr[2].scan(NAMED_ARG_RE).to_h { |m| {m[1], m[2]} }
          positional = named.empty? ? attr[2].scan(STRING_RE).map { |m| m[1]? || m[2] } : [] of String
          verb = named["verb"]? || positional[0]?
          url = named["url"]? || positional[1]?
          next unless verb && url
          url = route_url(id, attr[1] == "ApiRoute", named["root"]?, url)
          endpoints << endpoint(url, verb.upcase, Details.new(PathInfo.new(path, method.line)), {path, method})
        end
      end
    end

    # `route_url` with `{id}`-style params, plus the handler's other
    # arguments (Nextcloud fills them from the query string / body) and its
    # security attributes.
    private def endpoint(route_url : String, verb : String, details : Details,
                         method : {String, Noir::PhpClassMembers::Member}?) : Endpoint
      params = extract_brace_path_params(route_url)
      if method
        controller_path, member = method
        details.add_path(PathInfo.new(controller_path, member.line)) unless details.code_paths.first?.try(&.path) == controller_path
        arg_type = verb == "GET" || verb == "DELETE" ? "query" : "form"
        member.args.each do |arg|
          params << Param.new(arg, "", arg_type) unless params.any? { |p| p.name == arg }
        end
      end
      endpoint = Endpoint.new(route_url, verb, params, details)
      tag(endpoint, method[1].prelude) if method
      endpoint
    end

    private def tag(endpoint : Endpoint, prelude : String)
      if prelude.matches?(/\bPublicPage\b/)
        endpoint.add_tag(Tag.new("nextcloud-public-page", "Nextcloud PublicPage: reachable without login", TAGGER))
      else
        guard = if prelude.matches?(/\bAuthorizedAdminSetting\b/)
                  "delegated admin setting (AuthorizedAdminSetting)"
                elsif prelude.matches?(/\bNoAdminRequired\b/)
                  "login (NoAdminRequired)"
                else
                  "login + admin (default)"
                end
        endpoint.add_tag(Tag.new("auth", "Protected by Nextcloud #{guard}", TAGGER))
      end
      if prelude.matches?(/\bNoCSRFRequired\b/)
        endpoint.add_tag(Tag.new("nextcloud-no-csrf", "Nextcloud NoCSRFRequired: CSRF check disabled", TAGGER))
      end
    end

    # `url` under the app's prefix; Nextcloud keeps the trailing slash, so
    # `'/'` is `/apps/<id>/`.
    private def route_url(id : String, ocs : Bool, root : String?, url : String) : String
      root = nil unless ocs || ROOT_URL_APPS.includes?(id)
      "#{ocs ? OCS : ""}#{(root || "/apps/#{id}").rstrip('/')}/#{url.lchop('/')}"
    end

    # Each `[...]` element of the `'<group>' => [...]` array, with the
    # `'name' =>` key in front of it when the array is keyed (resources).
    private def each_group_entry(content : String, lexer : Noir::PhpLexer, group : String, &)
      open = find_key_array_open(content, lexer, group, 0, content.size) || return
      close = lexer.matching_delimiter(open) || return
      chars = lexer.masked
      i = open + 1
      while i < close
        if chars[i] == '['
          entry_close = lexer.matching_delimiter(i) || return
          key = lexer.source(Math.max(open + 1, i - 120)...i).match(RESOURCE_KEY).try(&.[1])
          yield i, entry_close, key
          i = entry_close + 1
        else
          i += 1
        end
      end
    end

    private def entry_fields(entry : String) : Hash(String, String)
      fields = {} of String => String
      entry.scan(ENTRY_KEY_RE) { |m| fields[m[1]] ||= m[2] }
      fields
    end

    # `note_api` + `get_all` → `NoteApiController::getAll` in the app.
    private def find_method(cache : Hash(String, Methods), root : String, controller : String, action : String)
      return if controller.empty? || action.empty?
      name = camel(controller)
      file = "#{name[0].upcase}#{name[1..]}Controller.php"
      # `OCA\<App>\Controller\<Name>Controller` autoloads from `lib/Controller/`.
      expected = File.join(root, "lib", "Controller", file)
      path = get_files_by_basename(file).find(&.==(expected)) || return
      methods = cache[path] ||= begin
        found = Methods.new
        each_method(read_file_content(path)) { |member| found[member.name.downcase] = member }
        found
      end
      member = methods[camel(action).downcase]? || return
      {path, member}
    end

    private def each_method(content : String, &)
      lexer = Noir::PhpLexer.new(content)
      masked = lexer.masked.join
      Noir::PhpClassMembers.class_bodies(lexer, masked).each do |open, close|
        Noir::PhpClassMembers.each(lexer, masked, open, close) do |member|
          yield member if member.method && !member.static
        end
      end
    end

    private def camel(name : String) : String
      name.gsub(/_([a-z])/) { |_, m| m[1].upcase }
    end
  end
end
