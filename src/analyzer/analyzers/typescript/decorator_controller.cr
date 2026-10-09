require "../javascript/nestjs"

module Analyzer::Typescript
  # Decorator-controller frameworks that are not NestJS — tsoa,
  # routing-controllers, Ts.ED, inversify-express-utils. They share Nest's
  # model (a class decorator carries the prefix, method decorators carry the
  # verb and path, argument decorators carry the params), so they ride the
  # Nest parser and differ only in names. Each claims just the files that
  # import its package, which is what keeps them off each other's and Nest's
  # `@Controller` / `@Get`.
  abstract class DecoratorController < Analyzer::Javascript::Nestjs
    # Argument decorator => {param type, name when the decorator has no
    # string argument}. A nil name falls back to the argument's identifier:
    # tsoa's `@Query() name?: string` is the query param `name`.
    alias ParamDecorators = Hash(String, Tuple(String, String?))

    # Group 1 decorator, group 3 its string argument, group 4 the identifier
    # of the argument it decorates. One level of nested parens is allowed in
    # the argument list (`@Body(new Pipe())`).
    def self.param_decorator_re(names : Enumerable(String)) : Regex
      Regex.new("@(#{names.join('|')})\\s*\\(\\s*(?:(['\"`])([^'\"`]+)\\2)?[^()]*(?:\\([^()]*\\)[^()]*)*\\)\\s*(?:(?:public|private|protected|readonly)\\s+)*([A-Za-z_$][\\w$]*)?")
    end

    # `from 'pkg'` / `require('pkg')` for the framework's package(s).
    abstract def import_re : Regex
    abstract def param_decorators : ParamDecorators
    abstract def param_decorator_re : Regex

    # `@Get('/')` under `@JsonController('/users')` registers `/users/`,
    # which Express (non-strict routing) also serves as `/users`; report
    # the bare form, as Midway does.
    def analyze
      strip_trailing_slashes(analyze_with_extensions([".ts"]))
    end

    private def strip_trailing_slashes(endpoints : Array(Endpoint)) : Array(Endpoint)
      endpoints.map do |endpoint|
        endpoint.url = endpoint.url.rstrip('/') if endpoint.url.size > 1
        endpoint
      end
    end

    protected def owns_source?(content : String) : Bool
      content.matches?(import_re)
    end

    private def extract_decorator_parameters(method_params : String, endpoint : Endpoint)
      method_params.scan(param_decorator_re) do |match|
        type, fallback = param_decorators[match[1]]
        name = match[3]? || fallback || match[4]?
        endpoint.push_param(Param.new(name, "", type)) if name
      end
    end

    # First `key: 'value'` in a bootstrap file that `gate` matches — the
    # framework's server-wide route prefix.
    private def prefix_from_bootstrap(content : String, gate : Regex, key : Regex) : GlobalPrefixConfig?
      return unless content.matches?(gate)
      if match = content.match(key)
        GlobalPrefixConfig.new(match[2], [] of GlobalPrefixExclude)
      end
    end
  end
end
