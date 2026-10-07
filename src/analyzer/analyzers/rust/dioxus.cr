require "./leptos"

module Analyzer::Rust
  # Dioxus fullstack server functions. `#[server]` takes the same arguments
  # as Leptos's (Dioxus parses them with the server_fn argument grammar) but
  # defaults to a JSON body. Dioxus 0.7 adds `#[get("/path/{id}?q&r")]` and
  # its siblings: the literal is an axum path plus the query fields, and
  # every function argument not bound by the path or the query travels in
  # the JSON body. Arguments after the literal (`auth: Session`) are
  # server-side extractors, not client input.
  class Dioxus < Leptos
    analyzer_for "rust_dioxus"

    protected def crate_dependencies : Array(String)
      ["dioxus"]
    end

    VERBS           = Set{"get", "post", "put", "delete", "patch"}
    VERB_ATTR_RE    = /#\s*\[\s*(?:\w+\s*::\s*)*(?:server|get|post|put|delete|patch)\b/
    PATH_CAPTURE_RE = %r{\{\*?(\w+)\}|(?:^|/)[:*](\w+)}

    # Rocket and actix spell their routes `#[get("/x")]` too, so a verb
    # attribute only counts in a file that names dioxus — a workspace whose
    # root manifest lists dioxus can still hold an actix crate.
    protected def file_has_routes?(source : String) : Bool
      source.matches?(VERB_ATTR_RE) && (source.includes?("dioxus") || super)
    end

    protected def default_body_location : String
      "json"
    end

    protected def route_endpoint(name : String, attr : LibTreeSitter::TSNode,
                                 function : LibTreeSitter::TSNode, source : String) : Endpoint?
      return super unless VERBS.includes?(name)
      return unless source.includes?("dioxus")
      literal = attribute_arguments(attr, source).first?.try(&.strip) || return
      return unless literal.starts_with?('"')

      path, _, query = unquote(literal).partition('?')
      bound = Set(String).new
      path.scan(PATH_CAPTURE_RE) { |m| bound << (m[1]? || m[2]) }

      params = [] of Param
      query.split('&').each do |field|
        next if field.empty?
        # `?:all` / `?{all}` binds the whole query string to one argument.
        if field.starts_with?(':') || field.starts_with?('{')
          bound << field.lchop(':').lchop('{').rchop('}')
          next
        end
        key, _, binding = field.partition('=')
        bound << (binding.empty? ? key : binding)
        params << Param.new(key, "", "query")
      end
      function_args(function, source).each do |arg|
        params << Param.new(arg, "", "json") unless bound.includes?(arg)
      end
      Endpoint.new(path, name.upcase, params)
    end
  end
end
