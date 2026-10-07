require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../utils/top_level_split"
require "../../../utils/url_path"

module Analyzer::Rust
  # Leptos `#[server]` functions. The `server_fn` macro mounts each one at
  # `{prefix}/{endpoint}`: `prefix` defaults to `/api` and `endpoint` to the
  # function name. With no explicit `endpoint` the macro also appends an
  # xxhash of `CARGO_MANIFEST_DIR` and the module path — that depends on the
  # directory the binary was built in, so it is left off and the URL carries
  # the stable part only.
  #
  # Arguments come in two spellings: the legacy positional
  # `#[server(StructName, "/prefix", "Encoding", "endpoint")]` and the keyed
  # `#[server(prefix = "/p", endpoint = "e", input = GetUrl)]`. The `input`
  # (or legacy encoding, or `protocol`) codec decides the method; every
  # function argument is a field of the request.
  class Leptos < RustEngine
    analyzer_for "rust_leptos"

    protected def crate_dependencies : Array(String)
      ["leptos"]
    end

    ARG_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace | Noir::TopLevelSplit::Nest::Angle,
      quotes: "\"")

    SERVER_ATTR_RE  = /#\s*\[\s*(?:\w+\s*::\s*)*server\b/
    CODEC_VERB_RE   = /\b(Get|Delete|Patch|Put|Websocket)/
    COMMENT_RE      = %r{//[^\n]*|/\*.*?\*/}m
    POSITIONAL_KEYS = {"name", "prefix", "encoding", "endpoint"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      return endpoints unless file_has_routes?(source)

      include_callee = callees_needed?
      test_regions = RustEngine.collect_cfg_test_regions(source)
      Noir::TreeSitter.parse_rust(source) do |root|
        each_routing_pair(root) do |attr, function|
          next if RustEngine.inside_test_region?(attr, test_regions)
          name = attribute_name(attr, source) || next
          arguments = attribute_arguments(attr, source)
          endpoint = route_endpoint(name, arguments, function, source) || next
          endpoint.details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(attr) + 1))
          attach_handler_callees(function, source, path, endpoint) if include_callee
          endpoints << endpoint
        end
      end
      endpoints
    end

    protected def file_has_routes?(source : String) : Bool
      source.matches?(SERVER_ATTR_RE)
    end

    # Default `input` codec of a bare `#[server]`: Leptos posts a urlencoded
    # form (`PostUrl`).
    protected def default_body_location : String
      "form"
    end

    protected def route_endpoint(name : String, arguments : Array(String),
                                 function : LibTreeSitter::TSNode, source : String) : Endpoint?
      return unless name == "server"
      fn_name = function_name(function, source) || return

      keyed = server_args(arguments)
      prefix = keyed["prefix"]? || "/api"
      url = Noir::URLPath.join_rooted(prefix, keyed["endpoint"]? || fn_name)

      codec = keyed["input"]? || keyed["encoding"]? || keyed["protocol"]?
      verb = codec.try(&.match(CODEC_VERB_RE)).try(&.[1])
      # A websocket server fn upgrades a GET; its arguments are a message
      # stream, not request fields.
      if verb == "Websocket"
        endpoint = Endpoint.new(url, "GET")
        endpoint.protocol = "ws"
        return endpoint
      end
      method = verb.try(&.upcase) || "POST"
      location =
        if method.in?("GET", "DELETE")
          "query"
        elsif codec.nil?
          default_body_location
        elsif codec.matches?(/Url|Multipart/i)
          "form"
        else
          "json"
        end

      params = function_args(function, source).map { |arg| Param.new(arg, "", location) }
      Endpoint.new(url, method, params)
    end

    # `#[server(...)]` arguments as `key => value`, string values unquoted.
    # Positional arguments are mapped onto `name`, `prefix`, `encoding` and
    # `endpoint` in that order, which is the legacy macro's signature.
    protected def server_args(arguments : Array(String)) : Hash(String, String)
      args = {} of String => String
      arguments.each_with_index do |arg, idx|
        if m = arg.match(/\A(\w+)\s*=\s*(.+)\z/m)
          args[m[1]] = unquote(m[2])
        elsif key = POSITIONAL_KEYS[idx]?
          args[key] = unquote(arg)
        end
      end
      args
    end

    protected def unquote(value : String) : String
      value = value.strip
      value.size >= 2 && value.starts_with?('"') && value.ends_with?('"') ? value[1...-1] : value
    end

    # Last path segment of the attribute (`server` for `#[leptos::server]`).
    private def attribute_name(attr_item : LibTreeSitter::TSNode, source : String) : String?
      attr = find_named_child(attr_item, "attribute") || return
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source).split("::").last.strip
        end
      end
      nil
    end

    # The attribute's argument list split at top-level commas; empty for a
    # bare `#[server]`.
    private def attribute_arguments(attr_item : LibTreeSitter::TSNode, source : String) : Array(String)
      attr = find_named_child(attr_item, "attribute")
      arguments = attr && Noir::TreeSitter.field(attr, "arguments")
      return [] of String unless arguments
      text = Noir::TreeSitter.node_text(arguments, source)[1...-1].gsub(COMMENT_RE, "")
      Noir::TopLevelSplit.split(text, ',', ARG_RULES).reject(&.empty?)
    end

    protected def function_name(function : LibTreeSitter::TSNode, source : String) : String?
      name = Noir::TreeSitter.field(function, "name") || return
      Noir::TreeSitter.node_text(name, source)
    end

    # Names of the function's plain `name: Type` parameters. Destructuring
    # patterns have no single field name and are skipped.
    protected def function_args(function : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      parameters = Noir::TreeSitter.field(function, "parameters") || return names
      Noir::TreeSitter.each_named_child(parameters) do |param|
        next unless Noir::TreeSitter.node_type(param) == "parameter"
        pattern = Noir::TreeSitter.field(param, "pattern") || next
        name = Noir::TreeSitter.node_text(pattern, source).sub(/\Amut\s+/, "")
        names << name if name.matches?(/\A[A-Za-z_]\w*\z/)
      end
      names
    end
  end
end
