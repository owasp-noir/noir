require "../../engines/php_engine"

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
  # `*.schema.yml`) that must never be treated as routes.
  class Drupal < PhpEngine
    # Drupal routing lives in YAML, not PHP; scan those files instead of
    # the engine's default `.php`-only set.
    protected def php_source_files : Array(String)
      get_files_by_extension(".yml") + get_files_by_extension(".yaml")
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".routing.yml") || path.ends_with?(".routing.yaml")

      analyze_routing_file(path)
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

          methods.each do |method|
            endpoints << Endpoint.new(route_path, method.upcase, params.dup, details.dup)
          end
        end
      rescue e
        logger.debug "Error parsing Drupal routing file #{path}: #{e}"
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
