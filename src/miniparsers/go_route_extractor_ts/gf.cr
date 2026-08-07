# Part of Noir::TreeSitterGoRouteExtractor: GoFrame (gf) bind and metadata routes.
module Noir
  module TreeSitterGoRouteExtractor
    # GoFrame's standardized routing: a request struct embeds `g.Meta`
    # whose struct tag carries the route (`path:"/x" method:"get"`), and
    # `group.Bind(controller)` wires every such method up. The tag *is*
    # the route definition — it's exactly what gf's own OpenAPI generator
    # reads — so we surface it directly. `params` are the struct's own
    # request fields (json-tag name or field name); the analyzer types
    # them by HTTP method.
    struct GfMetaRoute
      getter path : String
      getter methods : Array(String)
      getter line : Int32
      getter params : Array(String)

      def initialize(@path, @methods, @line, @params)
      end
    end

    def extract_gf_routes(source : String) : Array(Route)
      extract_scoped_routes(source, ScopedConfig.new(
        prefix_method: "Group",
        middleware_method: "Group",
        chain_prefix: true,
        # Only `BindHandler` registers a request handler (a real
        # endpoint). `BindMiddleware`/`BindMiddlewareDefault` and
        # `BindHookHandler` attach middleware/hooks to a path *pattern*
        # (e.g. the catch-all `/*any`) — they are not endpoints, so
        # keeping them here minted phantom routes in every gf app.
        bind_methods: ["BindHandler"],
        bind_method_verb: "ALL",
      ))
    end

    # GoFrame standardized routing: scan every `type X struct { ... }`
    # for an embedded `g.Meta` field whose tag declares a route
    # (`path:"/x" method:"get"`). Each such struct is one endpoint (or
    # several, when `method` lists more than one verb). The struct's own
    # named fields become request params. This is method-/group-agnostic
    # on purpose: the tag fully specifies the route, the same way gf's
    # OpenAPI generator treats it, so we don't need to resolve the
    # `group.Bind(...)` site (whose prefix is often a runtime config
    # value we can't see statically).
    def extract_gf_meta_routes(source : String) : Array(GfMetaRoute)
      results = [] of GfMetaRoute
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "type_spec"
          type_node = Noir::TreeSitter.field(node, "type")
          next if type_node.nil?
          tn = type_node
          next unless Noir::TreeSitter.node_type(tn) == "struct_type"

          field_list = nil
          Noir::TreeSitter.each_named_child(tn) do |c|
            if Noir::TreeSitter.node_type(c) == "field_declaration_list"
              field_list = c
              break
            end
          end
          fl = field_list
          next if fl.nil?

          meta_tag = nil
          meta_line = Noir::TreeSitter.node_start_row(node)
          params = [] of String

          Noir::TreeSitter.each_named_child(fl) do |decl|
            next unless Noir::TreeSitter.node_type(decl) == "field_declaration"

            tag = ""
            if tag_node = Noir::TreeSitter.field(decl, "tag")
              tag = Noir::TreeSitter.node_text(tag_node, source).gsub(/^[`"]|[`"]$/, "")
            end

            if name_node = Noir::TreeSitter.field(decl, "name")
              # A genuine named request field — its json tag (or, lacking
              # one, the field name) is a request param.
              next if tag.includes?("path:") # defensive: not the meta line
              field_name = Noir::TreeSitter.node_text(name_node, source)
              pname = if m = tag.match(/json:"([^",]+)/)
                        m[1]
                      else
                        field_name
                      end
              params << pname unless pname.empty? || pname == "-"
            elsif type_node2 = Noir::TreeSitter.field(decl, "type")
              # Embedded field. The `g.Meta` carrier holds the route tag;
              # other embeds (`adminin.FooInp`) bring fields we can't see
              # cheaply, so they're skipped for params.
              embed_type = Noir::TreeSitter.node_text(type_node2, source)
              if (embed_type == "g.Meta" || embed_type.ends_with?(".Meta")) && tag.includes?("path:")
                meta_tag = tag
                meta_line = Noir::TreeSitter.node_start_row(decl)
              end
            end
          end

          mt = meta_tag
          next if mt.nil?
          path_match = mt.match(/path:"([^"]+)"/)
          next if path_match.nil?
          path = path_match[1]
          next unless path.starts_with?("/")

          methods = if mm = mt.match(/method:"([^"]+)"/)
                      mm[1].split(',').map(&.strip.upcase).reject(&.empty?)
                    else
                      [] of String
                    end
          # A method-less g.Meta route responds to ALL HTTP methods in
          # gf; represent that as "ALL" so the analyzer fans it out to
          # every canonical verb (rather than guessing a single one).
          methods = ["ALL"] if methods.empty?

          results << GfMetaRoute.new(path, methods, meta_line, params)
        end
      end
      results
    end
  end
end
