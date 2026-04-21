module Noir
  # Pure parsing helpers for Python framework route idioms.
  #
  # Framework adapters (Flask, Sanic, …) iterate source files and call
  # these helpers per line. The extractor has no file I/O, no `Analyzer`
  # dependency, and no framework-specific state — it just recognizes
  # the three most common Python route-related idioms so adapters stop
  # duplicating the regexes:
  #
  #   1. `@<var>.route("/path", methods=[...])`
  #   2. `@<var>.<method>("/path")`     # method in {get, post, …}
  #   3. `<var> = Blueprint(url_prefix="…")`
  #
  # Plus a helper to locate the `def`/`class` that a decorator applies to.
  #
  # This is the Python analogue of `js_route_extractor.cr` / `go_route_extractor.cr`.
  # Framework-specific behaviour (flask_restx, Sanic's class views, cross-file
  # `register_blueprint`, etc.) stays in the adapters.
  module PythonRouteExtractor
    extend self

    PYTHON_VAR_NAME = /[a-zA-Z_][a-zA-Z0-9_]*/
    HTTP_METHODS    = %w[get post put patch delete head options trace]

    # One match from `scan_decorators`.
    #
    # `router_name` is the variable before `.route` / `.get` / …. `path` is
    # the string literal argument. `extra_params` is the raw tail of the
    # decorator call (everything after the path and its closing quote) so
    # callers can parse `methods=[...]` out of it; for method-specific
    # decorators the extractor fills it with `methods=['METHOD']` so the
    # adapter can treat both idioms uniformly.
    struct Decoration
      getter router_name : String
      getter path : String
      getter extra_params : String

      def initialize(@router_name, @path, @extra_params)
      end
    end

    # Scan one line for `@<var>.route(...)` and `@<var>.<method>(...)` and
    # return every decorator found. Typically 0 or 1 per line.
    #
    # `original_line` defaults to `line`. Callers that have space-stripped
    # `line` for regex-matching convenience should pass the original here
    # so paths that contain spaces survive (Flask does this; Sanic doesn't
    # need to because its fixtures never have space-bearing paths).
    def scan_decorators(line : String, original_line : String? = nil) : Array(Decoration)
      results = [] of Decoration
      source = original_line || line

      line.scan(/@(#{PYTHON_VAR_NAME})\.route\([rf]?['"]([^'"]*)['"](.*)/) do |match|
        next unless match.size > 0
        router_name = match[1]
        path = match[2]
        if original_line
          if source_match = source.match(/@#{router_name}\.route\(\s*[rf]?['"]([^'"]*)['"]/)
            path = source_match[1]
          end
        end
        results << Decoration.new(router_name, path, match[3])
      end

      HTTP_METHODS.each do |method|
        line.scan(/@(#{PYTHON_VAR_NAME})\.#{method}\([rf]?['"]([^'"]*)['"](.*)/) do |match|
          next unless match.size > 0
          router_name = match[1]
          path = match[2]
          if original_line
            if source_match = source.match(/@#{router_name}\.#{method}\(\s*[rf]?['"]([^'"]*)['"]/)
              path = source_match[1]
            end
          end
          results << Decoration.new(router_name, path, "methods=['#{method.upcase}']")
        end
      end

      results
    end

    # Detect a `<name> = (module.)?Blueprint(url_prefix="...")` assignment.
    # Returns `{name, prefix}` if matched, `nil` otherwise.
    #
    # `module_names` is the list of optional module prefixes a framework
    # allows — Flask accepts `flask.Blueprint`, Sanic accepts `sanic.Blueprint`,
    # or a bare `Blueprint` after an `import`.
    #
    # `original_line` is used to read `url_prefix`, so if the caller
    # space-stripped `line`, spaces inside the prefix value still survive.
    def scan_blueprint(line : String, module_names : Array(String), original_line : String? = nil) : Tuple(String, String)?
      mod_alt = module_names.map { |m| Regex.escape(m) }.join("|")
      re = Regex.new("(#{PYTHON_VAR_NAME.source})(?::#{PYTHON_VAR_NAME.source})?=(?:(?:#{mod_alt})\\.)?Blueprint\\(")
      match = line.match(re)
      return unless match

      name = match[1]
      prefix = ""
      source = original_line || line
      if param_codes = source.split("Blueprint", 2)[1]?
        if prefix_match = param_codes.match(/url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/)
          prefix = prefix_match[1]
        end
      end
      {name, prefix}
    end

    # Locate the `def`/`async def`/`class` that a decorator applies to.
    #
    # `direction: :down` walks forward past additional decorators and blank
    # lines, stopping at the first non-decorator line (the one we want, or
    # something that breaks the decorator chain). `direction: :up` walks
    # backward, used when the decorator sits on a method whose enclosing
    # class was found elsewhere.
    #
    # Returns the index of the def/class line, or the original `line_index`
    # when nothing matches.
    def find_def_line(lines : Array(String), line_index : Int32, direction : Symbol = :down) : Int32
      case direction
      when :down
        i = line_index + 1
        while i < lines.size
          stripped = lines[i].lstrip
          if stripped.starts_with?("def ") || stripped.starts_with?("async def ") || stripped.starts_with?("class ")
            return i
          end
          if stripped.starts_with?("@") || stripped.empty?
            i += 1
            next
          end
          break
        end
      when :up
        i = line_index - 1
        while i >= 0
          stripped = lines[i].lstrip
          if stripped.starts_with?("def ") || stripped.starts_with?("async def ") || stripped.starts_with?("class ")
            return i
          end
          i -= 1
        end
      end
      line_index
    end
  end
end
