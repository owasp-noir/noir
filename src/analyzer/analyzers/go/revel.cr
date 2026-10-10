require "../../engines/go_engine"
require "../../engines/play_route_support"

module Analyzer::Go
  # Revel (https://revel.github.io/manual/routing.html) declares every route
  # in a Play-style `conf/routes` file next to the app's `app/` directory:
  #
  #   GET     /users/:id              Users.Show
  #   WS      /feed                   App.Feed
  #   *       /:controller/:action    :controller.:action
  #   module:testrunner
  #
  # The routes file is claimed only when Go code under the sibling `app/`
  # imports Revel, so a Play app's `conf/routes` is left to Play.
  class Revel < GoEngine
    analyzer_for "go_revel"

    include PlayRouteSupport

    MARKER    = "github.com/revel/revel"
    TAGGER    = "revel_analyzer"
    ROUTE_RE  = /\A(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|WS|\*)\s+(\S+)\s+(\S+)/
    ACTION_RE = /^func\s*\(\s*\w+\s+\*?(\w+)\s*\)\s*(\w+)\s*\(([^)]*)\)\s*revel\.Result/m

    def analyze
      go_files = get_files_by_extension(".go").reject { |path| GoEngine.go_test_file?(base_relative_path(path)) }

      get_files_by_basename("routes").each do |routes|
        conf = File.dirname(routes)
        next unless File.basename(conf) == "conf"

        app_dir = "#{File.dirname(conf)}/app/"
        sources = go_files.select(&.starts_with?(app_dir)).map { |path| read_file_content(path) }
        next unless sources.any?(&.includes?(MARKER))

        emit_routes(routes, action_params(sources))
      end
      result
    end

    # `Controller.Action` => argument names. Revel binds action arguments
    # from the path, query string and form by name; a `revel.*`-typed one
    # (`ws revel.ServerWebSocket`) is injected by the framework instead.
    private def action_params(sources : Array(String)) : Hash(String, Array(String))
      actions = Hash(String, Array(String)).new
      sources.each do |source|
        source.scan(ACTION_RE) do |match|
          actions["#{match[1]}.#{match[2]}"] = match[3].split(',').compact_map do |arg|
            words = arg.split
            words.first? unless words[1]?.try(&.includes?("revel."))
          end
        end
      end
      actions
    end

    private def emit_routes(path : String, actions : Hash(String, Array(String)))
      read_file_content(path).each_line.with_index(1) do |line, number|
        next unless match = line.strip.match(ROUTE_RE)
        action = match[3]
        next if action.starts_with?("module:")

        method = case match[1]
                 when "*"  then "ANY"
                 when "WS" then "GET"
                 else           match[1]
                 end
        endpoint = Endpoint.new(match[2], method, Details.new(PathInfo.new(path, number)))
        endpoint.protocol = "ws" if match[1] == "WS"
        extract_path_params(endpoint, match[2])

        if action.starts_with?(':')
          endpoint.add_tag(Tag.new("catch-all", "Revel dynamic :controller.:action route", TAGGER))
        else
          location = method == "GET" ? "query" : "form"
          actions[action.split('(').first]?.try &.each do |name|
            endpoint.push_param(Param.new(name, "", location)) unless endpoint.params.any? { |param| param.name == name }
          end
        end
        result << endpoint
      end
    end
  end
end
