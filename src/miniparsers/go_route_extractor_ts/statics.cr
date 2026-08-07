# Part of Noir::TreeSitterGoRouteExtractor: static-file registrations (gin/goyave/mux, http.Dir).
module Noir
  module TreeSitterGoRouteExtractor
    # `<router>.<method_name>("/prefix", "./dir", ...)`. The first two
    # string args are taken as `(url_prefix, disk_path)`. Covers the
    # Gin/Echo/Fiber/Hertz/GoZero shape.
    def extract_simple_statics(source : String, method_name : String = "Static") : Array(StaticPath)
      results = [] of StaticPath
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if sp = decode_simple_static(node, source, method_name)
            results << sp
          end
        end
      end
      results
    end

    # Goyave-style `<router>.Static(&fs, "/prefix", false)`: the first
    # `/`-prefixed string argument is the URL prefix; the disk path is
    # derived by stripping its leading slash (matching the legacy
    # extractor's behaviour, which used the same identifier for both).
    def extract_goyave_statics(source : String) : Array(StaticPath)
      results = [] of StaticPath
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if sp = decode_goyave_static(node, source)
            results << sp
          end
        end
      end
      results
    end

    # Mux-style `<router>.PathPrefix("/x/").Handler(<... http.Dir("./x/") ...>)`.
    # URL prefix comes from the `PathPrefix` arg; disk path from the
    # `http.Dir(...)` call nested somewhere inside the `Handler(...)`
    # argument expression.
    def extract_mux_statics(source : String) : Array(StaticPath)
      results = [] of StaticPath
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if sp = decode_mux_static(node, source)
            results << sp
          end
        end
      end
      results
    end

    # Decode `<router>.<method_name>("/prefix", "./dir", ...)`. The legacy
    # path extractor also stripped leading `./` and collapsed repeated
    # slashes in the disk path; we reproduce that here to stay
    # byte-compatible with downstream `resolve_public_dirs` behaviour.
    private def decode_simple_static(call : LibTreeSitter::TSNode,
                                     source : String,
                                     method_name : String) : StaticPath?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless Noir::TreeSitter.node_text(field, source) == method_name

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      strings = [] of String
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          strings << decode_string_literal(arg, source)
          break if strings.size >= 2
        end
      end
      return if strings.size < 2

      url_prefix = strings[0]
      disk_path = strings[1].gsub(%r{//+}, "/")
      StaticPath.new(url_prefix, disk_path, Noir::TreeSitter.node_start_row(call))
    end

    # Decode goyave-style `<router>.Static(&fs, "/prefix", false)` — the
    # prefix is a `/`-leading string positional arg anywhere in the list.
    # The legacy impl derived the disk path by stripping the leading
    # slash, so we do the same.
    private def decode_goyave_static(call : LibTreeSitter::TSNode,
                                     source : String) : StaticPath?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless Noir::TreeSitter.node_text(field, source) == "Static"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      prefix = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          candidate = decode_string_literal(arg, source)
          if candidate.starts_with?('/')
            prefix = candidate
            break
          end
        end
      end
      return unless prefix
      StaticPath.new(prefix, prefix.lchop('/'), Noir::TreeSitter.node_start_row(call))
    end

    # Decode mux's `<router>.PathPrefix("/x/").Handler(... http.Dir("./x/") ...)`.
    # We recognise the outer `.Handler(...)` call whose operand is the
    # `.PathPrefix(...)` call, then walk the handler argument subtree to
    # find the nested `http.Dir(...)` for the disk path.
    private def decode_mux_static(call : LibTreeSitter::TSNode,
                                  source : String) : StaticPath?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      outer_field = Noir::TreeSitter.field(function, "field")
      return unless outer_field
      return unless Noir::TreeSitter.node_text(outer_field, source) == "Handler"

      pathprefix_call = Noir::TreeSitter.field(function, "operand")
      return unless pathprefix_call
      return unless Noir::TreeSitter.node_type(pathprefix_call) == "call_expression"

      pp_fn = Noir::TreeSitter.field(pathprefix_call, "function")
      return unless pp_fn
      return unless Noir::TreeSitter.node_type(pp_fn) == "selector_expression"
      pp_field = Noir::TreeSitter.field(pp_fn, "field")
      return unless pp_field
      return unless Noir::TreeSitter.node_text(pp_field, source) == "PathPrefix"

      pp_args = Noir::TreeSitter.field(pathprefix_call, "arguments")
      return unless pp_args
      url_prefix = nil
      Noir::TreeSitter.each_named_child(pp_args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          url_prefix = decode_string_literal(arg, source)
          break
        end
      end
      return unless url_prefix

      handler_args = Noir::TreeSitter.field(call, "arguments")
      return unless handler_args

      disk_path = find_http_dir_arg(handler_args, source)
      return unless disk_path
      disk_path = disk_path.lchop("./")
      StaticPath.new(url_prefix, disk_path, Noir::TreeSitter.node_start_row(call))
    end

    # Recursively search `node` for a `http.Dir("...")` call and return
    # its first string argument. Used by the mux static decoder.
    private def find_http_dir_arg(node : LibTreeSitter::TSNode, source : String) : String?
      if Noir::TreeSitter.node_type(node) == "call_expression"
        if fn = Noir::TreeSitter.field(node, "function")
          if Noir::TreeSitter.node_type(fn) == "selector_expression"
            operand = Noir::TreeSitter.field(fn, "operand")
            fld = Noir::TreeSitter.field(fn, "field")
            if operand && fld &&
               Noir::TreeSitter.node_type(operand) == "identifier" &&
               Noir::TreeSitter.node_text(operand, source) == "http" &&
               Noir::TreeSitter.node_text(fld, source) == "Dir"
              if args = Noir::TreeSitter.field(node, "arguments")
                Noir::TreeSitter.each_named_child(args) do |arg|
                  case Noir::TreeSitter.node_type(arg)
                  when "interpreted_string_literal", "raw_string_literal"
                    return decode_string_literal(arg, source)
                  end
                end
              end
            end
          end
        end
      end

      result : String? = nil
      Noir::TreeSitter.each_named_child(node) do |child|
        if found = find_http_dir_arg(child, source)
          result = found
          break
        end
      end
      result
    end

    # ---------------------------------------------------------------------
    # net/http (stdlib) support — dedicated, isolated from chi/mux/etc.
    # ---------------------------------------------------------------------

  end
end
