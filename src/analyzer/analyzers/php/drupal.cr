require "../../engines/php_engine"
require "./symfony_route_attributes"

module Analyzer::Php
  # Drupal 8+ attack-surface extractor.
  #
  # Drupal declares its routes in `MODULE.routing.yml` files built on
  # top of the Symfony routing component. Each top-level key is a route
  # name whose value carries a `path`, an optional `methods` list, and a
  # `defaults`/`requirements` block:
  #
  #   example.content:
  #     path: '/example/{id}'
  #     defaults:
  #       _controller: '\Drupal\example\Controller\ExampleController::view'
  #     methods: [GET]
  #     requirements:
  #       _permission: 'access content'
  #
  # We parse only `*.routing.yml` files — a Drupal tree carries many
  # other YAML files (`*.info.yml`, `*.services.yml`, `*.libraries.yml`,
  # `*.schema.yml`) that must never be treated as routes. Drupal 10.? and
  # later also take Symfony's `#[Route(...)]` attribute on controller
  # methods, read from `.php` files.
  #
  # A route's `requirements` are its access checks: `_permission`, `_role`,
  # `_entity_access` and the like are authorization, `_user_is_logged_in:
  # 'TRUE'` authentication. `_access: 'TRUE'` lets anyone in.
  class Drupal < PhpEngine
    analyzer_for "php_drupal"

    include SymfonyRouteAttributes

    TAGGER = "drupal_analyzer"

    # Requirement keys that check the request, not who makes it, or that
    # let an anonymous caller in (`_access_user_register` while registration
    # is open; `_access_system_cron` takes a cron key, not a user).
    NON_ACCESS_REQUIREMENTS = Set{"_access", "_format", "_content_type_format", "_method", "_module_dependencies",
                                  "_csrf_token", "_csrf_request_header_token", "_access_rest_csrf", "_user_is_logged_in",
                                  "_entity_bundles", "_access_user_register", "_access_theme", "_access_system_cron"}

    # Drupal routing lives in YAML; `#[Route]` controllers are `.php`.
    protected def php_source_files : Array(String)
      get_files_by_extension(".yml") + get_files_by_extension(".yaml") + get_files_by_extension(".php")
    end

    def analyze_file(path : String) : Array(Endpoint)
      return analyze_routing_file(path) if path.ends_with?(".routing.yml") || path.ends_with?(".routing.yaml")
      return analyze_route_attributes(path) if path.ends_with?(".php")
      [] of Endpoint
    end

    # Controller methods carrying `#[Route(path: ..., methods: ..., requirements: [...])]`.
    private def analyze_route_attributes(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = read_file_content(path)
      return endpoints unless content.includes?("#[Route")
      lexer = Noir::PhpLexer.new(content)
      content = lexer.without_comments
      route_attributes(content, lexer).each do |attr|
        # ponytail: a class-level `#[Route]` (a prefix) is skipped, not applied.
        next if route_applies_to_class?(content, attr.stop)
        next unless content[attr.start, 2] == "#["
        next unless route_path = extract_symfony_route_path(attr.args).presence
        methods = extract_methods_from_symfony_context(attr.args)
        methods = ["GET"] if methods.empty?
        requirements = {} of String => String
        if expr = attribute_args(attr.args)[0]["requirements"]?
          expr.scan(/['"](\w+)['"]\s*=>\s*(?:'([^']*)'|"([^"]*)")/) { |m| requirements[m[1]] = m[2]? || m[3] }
        end
        details = Details.new(PathInfo.new(path, line_number_for_index(content, attr.start)))
        methods.each do |method|
          endpoint = Endpoint.new(route_path, method.upcase, extract_route_params(route_path), details.dup)
          tag_requirements(endpoint, requirements)
          endpoints << endpoint
        end
      end
      endpoints
    end

    # Tags the guard each access check in `requirements` imposes. Under
    # `options: _access_mode: ANY` one passing check is enough, so a route
    # with any open check (or several) is left untagged.
    private def tag_requirements(endpoint : Endpoint, requirements : Hash(String, String), any_mode : Bool = false)
      return if any_mode
      if requirements["_user_is_logged_in"]?.try(&.strip.upcase) == "TRUE"
        endpoint.add_tag(Tag.new("auth", "Protected by Drupal _user_is_logged_in", TAGGER))
      end
      requirements.each do |key, value|
        next if !key.starts_with?('_') || NON_ACCESS_REQUIREMENTS.includes?(key)
        endpoint.add_tag(Tag.new("authz", "Protected by Drupal #{key} (#{value})", TAGGER))
      end
    end

    private def analyze_routing_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      begin
        content = read_file_content(path)
        yaml = YAML.parse(content)
        routes = yaml.as_h?
        return endpoints unless routes

        routes.each do |_name, route|
          route_h = route.as_h?
          next unless route_h

          route_path = route_h[YAML::Any.new("path")]?.try(&.as_s?)
          next unless route_path
          next if route_path.empty?

          methods = extract_methods(route_h[YAML::Any.new("methods")]?)
          # Drupal defaults to responding on all verbs when `methods` is
          # omitted; match the existing Symfony YAML analyzer and default
          # to GET to avoid method explosion.
          methods = ["GET"] if methods.empty?

          params = extract_route_params(route_path)
          requirements = {} of String => String
          any_mode = route_h[YAML::Any.new("options")]?.try(&.as_h?).try(&.[YAML::Any.new("_access_mode")]?).try(&.raw.to_s.upcase) == "ANY"
          route_h[YAML::Any.new("requirements")]?.try(&.as_h?).try &.each do |key, value|
            requirements[key.to_s] = value.raw.to_s if key.as_s?
          end

          methods.each do |method|
            endpoint = Endpoint.new(route_path, method.upcase, params.dup, details.dup)
            tag_requirements(endpoint, requirements, any_mode)
            endpoints << endpoint
          end
        end
      rescue e
        logger.debug "Error parsing Drupal routing file #{path}: #{e}"
        Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      end

      endpoints
    end

    private def extract_methods(node : YAML::Any?) : Array(String)
      return [] of String unless node

      if list = node.as_a?
        list.compact_map(&.as_s?).reject(&.empty?)
      elsif single = node.as_s?
        single.empty? ? [] of String : [single]
      else
        [] of String
      end
    end

    # Drupal path parameters use `{name}` placeholders (e.g.
    # `/node/{node}/edit`). Deduplicate repeated names.
    private def extract_route_params(route_path : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new
      route_path.scan(/\{(\w+)\}/) do |m|
        name = m[1]
        next if seen.includes?(name)
        seen.add(name)
        params << Param.new(name, "", "path")
      end
      params
    end
  end
end
