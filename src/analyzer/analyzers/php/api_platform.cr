require "../../engines/php_engine"
require "../../../minilexers/php_lexer"
require "../../../utils/top_level_split"

module Analyzer::Php
  # API Platform builds its HTTP API from class-level resource metadata
  # instead of controller routes:
  #
  #     #[ApiResource(operations: [new Get(), new Post(uriTemplate: '/books/new')])]
  #     #[GetCollection(uriTemplate: '/authors/{authorId}/books')]
  #     class Book { … }
  #
  # An operation without its own `uriTemplate` inherits the resource's, and
  # without either one it gets the generated `/{short_names}` (collection,
  # POST) or `/{short_names}/{id}` (item) path. `routePrefix` and the
  # `type: api_platform` route import's `prefix` (`/api` in the Symfony
  # recipe, `route_prefix` in Laravel's config/api-platform.php) sit in front.
  class ApiPlatform < PhpEngine
    analyzer_for "php_api_platform"

    OPERATION_METHODS = {
      "Get"           => "GET",
      "GetCollection" => "GET",
      "Post"          => "POST",
      "Put"           => "PUT",
      "Patch"         => "PATCH",
      "Delete"        => "DELETE",
      "HttpOperation" => "GET",
    }
    COLLECTION_OPERATIONS = {"GetCollection", "Post"}
    # API Platform 4's defaults; 3.x also added Put.
    DEFAULT_OPERATIONS      = %w[Get GetCollection Post Patch Delete]
    ENUM_DEFAULT_OPERATIONS = %w[GetCollection Get]
    PARAMETER_TYPES         = {"QueryParameter" => "query", "HeaderParameter" => "header"}

    # `HttpOperation` is not an attribute class, so it only counts inside
    # `operations:` lists.
    ATTRIBUTE_RE   = /#\[\s*(\\?(?:[\w\\]+\\)?)(ApiResource|GetCollection|Get|Post|Put|Patch|Delete)\s*(\(|\])/
    DECLARATION_RE = /(?<![\w:$>])(class|enum|interface|trait|function)\b(?!\s*:(?!:))\s*(\w*)/
    IMPORT_RE      = /^\s*use\s+\\?ApiPlatform\\Metadata(?:\\(\w+)|\\\{([^}]*)\}|\s+as\s+(\w+))?\s*;/m
    IDENTIFIER_RE  = /\bApiProperty\s*\([^)]*\bidentifier\s*:\s*true\b[^$]*?\$(\w+)/
    ORM_ID_RE      = /#\[\s*(?:[\w\\]*\\)?Id\s*\][^$]*?\$(\w+)/
    NEW_RE         = /\A(?:['"][^'"]*['"]\s*=>\s*)?new\s+\\?(?:[\w\\]+\\)?(\w+)\s*(\()?/
    NAMED_ARG_RE   = /\A(\w+)\s*:(?!:)\s*(.*)\z/m
    STRING_RE      = /\A(['"])((?:(?!\1).)*)\1\z/m
    FORMAT_RE      = /\{\._format\}|\.\{_format\}/
    ARGS_RULES     = Noir::TopLevelSplit::Rules.new(strip: false)

    private record Operation, kind : String, args : String, line : Int32
    # `declared` is an explicit `operations:` list; a resource with neither
    # that nor standalone operation attributes gets the defaults.
    private record Resource, short_name : String, uri_template : String?, route_prefix : String?,
      parameters : Array(Param), line : Int32, declared : Bool, operations : Array(Operation),
      identifier : String
    # Laravel's `route_prefix` is only the default for `routePrefix`, which
    # replaces it; Symfony's route-import prefix sits in front of it.
    private record Prefix, path : String, replaceable : Bool

    @prefixes = {} of String => Prefix

    def analyze
      @prefixes = route_prefixes
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = read_file_content(path)
      return endpoints unless content.includes?("ApiPlatform") && content.includes?("#[")
      imported, aliases = imports(content)
      return endpoints if imported.empty? && aliases.empty?

      lexer = Noir::PhpLexer.new(content)
      text, scan = searchable(content, lexer)
      prefix = prefix_for(path)
      # Resources of the class currently being collected, keyed by the
      # position of its `class`/`enum` keyword.
      resources = [] of Resource
      class_pos = -1
      is_enum = false
      identifier = "id"
      flush = -> do
        resources.each { |resource| emit_resource(endpoints, path, prefix, resource, is_enum) }
        resources.clear
      end

      offset = 0
      while match = ATTRIBUTE_RE.match_at_byte_index(scan, offset, options: NO_UTF_CHECK)
        offset = match.end(0)
        attr_start = match.begin(0)
        next unless lexer.in_code?(attr_start + 1)
        qualifier = match[1].lchop('\\')
        next unless qualifier.empty? ? imported.includes?(match[2]) : (qualifier == "ApiPlatform\\Metadata\\" || aliases.includes?(qualifier))

        args = ""
        if match[3] == "("
          close = lexer.matching_delimiter(match.end(0) - 1)
          next unless close
          args = text[match.end(0)...close]
          offset = close
        end
        # Only class-level attributes describe resources; a `#[Get]` on a
        # method belongs to some other library (FOSRest, Symfony's own).
        declaration = next_declaration(scan, lexer, offset)
        next unless declaration
        keyword, class_name, decl_pos = declaration
        next if class_name.empty? || !{"class", "enum"}.includes?(keyword)
        if decl_pos != class_pos
          flush.call
          class_pos = decl_pos
          is_enum = keyword == "enum"
          identifier = identifier_of(scan, lexer, decl_pos)
        end

        line = line_number_for_index(scan, attr_start)
        if match[2] == "ApiResource"
          named, positional = split_args(args)
          operations = [] of Operation
          if list = named["operations"]?
            list_start = match.end(0) + (args.index(list) || 0)
            each_operation(list) do |kind, op_args, op_offset|
              operations << Operation.new(kind, op_args, line_number_for_index(scan, list_start + op_offset))
            end
          end
          resources << Resource.new(
            literal(named["shortName"]?) || class_name,
            literal(named["uriTemplate"]? || positional.first?),
            literal(named["routePrefix"]?),
            parameters(named["parameters"]?),
            line, named.has_key?("operations"), operations, identifier)
        else
          # A standalone operation attribute joins the resource declared
          # above it, or forms a resource of its own.
          if resources.empty?
            resources << Resource.new(class_name, nil, nil, [] of Param, line, false, [] of Operation, identifier)
          end
          resources.last.operations << Operation.new(match[2], args, line)
        end
      end
      flush.call

      endpoints
    rescue e
      logger.debug "Error analyzing API Platform resource #{path}: #{e}"
      [] of Endpoint
    end

    # Names imported from `ApiPlatform\Metadata` and aliases of the namespace
    # itself (`use ApiPlatform\Metadata as API;` -> `API\`).
    private def imports(content : String) : Tuple(Set(String), Set(String))
      imported = Set(String).new
      aliases = Set(String).new
      content.scan(IMPORT_RE) do |m|
        if name = m[1]?
          imported << name
        elsif group = m[2]?
          group.split(",") { |entry| imported << entry.strip.split(/\s+as\s+/).first }
        elsif alias_name = m[3]?
          aliases << "#{alias_name}\\"
        end
      end
      {imported, aliases}
    end

    # `content` with comments blanked (so they can't leak into argument
    # lists), and an ASCII copy of it for searching: char offsets equal byte
    # offsets there, so per-match regex/slice work stays O(1) to locate on
    # files with CJK comments. Both keep the lexer's character offsets.
    private def searchable(content : String, lexer : Noir::PhpLexer) : Tuple(String, String)
      return {content, content} if lexer.spans.none? { |span| span[0] == :comment } && content.bytesize == content.size

      chars = content.chars
      lexer.spans.each do |(kind, from, to)|
        next unless kind == :comment
        (from...to).each { |i| chars[i] = ' ' unless chars[i] == '\n' }
      end
      text = chars.join
      return {text, text} if text.bytesize == text.size
      {text, chars.map { |c| c.ascii? ? c : '?' }.join}
    end

    # The URI variable of generated item paths: an `#[ApiProperty(identifier:
    # true)]` property, else the Doctrine `#[ORM\Id]` one, else `id`.
    private def identifier_of(scan : String, lexer : Noir::PhpLexer, decl_pos : Int32) : String
      open = scan.index('{', decl_pos)
      close = open && lexer.matching_delimiter(open)
      return "id" unless open && close

      body = scan[open...close]
      (body.match(IDENTIFIER_RE) || body.match(ORM_ID_RE)).try(&.[1]) || "id"
    end

    private def emit_resource(endpoints : Array(Endpoint), path : String, prefix : Prefix, resource : Resource, is_enum : Bool)
      if resource.declared || !resource.operations.empty?
        resource.operations.each { |op| emit(endpoints, path, op.line, prefix, resource, op.kind, op.args) }
      else
        defaults = is_enum ? ENUM_DEFAULT_OPERATIONS : DEFAULT_OPERATIONS
        defaults.each { |kind| emit(endpoints, path, resource.line, prefix, resource, kind, "") }
      end
    end

    # `scan` is ASCII, so byte offsets are char offsets; skipping PCRE2's
    # per-call UTF validation keeps the attribute walk linear.
    NO_UTF_CHECK = Regex::MatchOptions::NO_UTF_CHECK

    # First declaration keyword in code after `offset`: `{keyword, name, position}`.
    private def next_declaration(content : String, lexer : Noir::PhpLexer, offset : Int32) : Tuple(String, String, Int32)?
      while m = DECLARATION_RE.match_at_byte_index(content, offset, options: NO_UTF_CHECK)
        return {m[1], m[2], m.begin(0)} if lexer.in_code?(m.begin(0))
        offset = m.end(0)
      end
    end

    private def emit(endpoints : Array(Endpoint), path : String, line : Int32, prefix : Prefix,
                     resource : Resource, kind : String, args : String)
      method = OPERATION_METHODS[kind]?
      return unless method

      named, positional = split_args(args)
      # A `routeName` operation reuses an existing route instead of getting one.
      return if named.has_key?("routeName")
      if kind == "HttpOperation"
        raw = named["method"]? || positional.first?
        method = (literal(raw) || raw.try(&.[/METHOD_(\w+)/, 1]?) || method).upcase
        positional = positional.skip(1)
      end

      short_name = literal(named["shortName"]?) || resource.short_name
      uri = literal(named["uriTemplate"]? || positional.first?) || resource.uri_template
      collection = COLLECTION_OPERATIONS.includes?(kind) || method == "POST"
      uri ||= "/#{segment(short_name)}#{collection ? "" : "/{#{resource.identifier}}"}"
      uri = uri.gsub(FORMAT_RE, "")
      route_prefix = literal(named["routePrefix"]?) || resource.route_prefix

      url =
        if route_prefix && prefix.replaceable
          build_full_path(route_prefix, uri)
        else
          build_full_path(build_full_path(prefix.path, route_prefix || ""), uri)
        end
      params = extract_brace_path_params(url) + resource.parameters + parameters(named["parameters"]?)
      endpoints << Endpoint.new(url, method, dedup_params(params), Details.new(PathInfo.new(path, line)))
    end

    # Named (`key: value`) and positional arguments of an attribute or `new`
    # call, as raw source text.
    private def split_args(args : String) : Tuple(Hash(String, String), Array(String))
      named = {} of String => String
      positional = [] of String
      Noir::TopLevelSplit.split(args, ',', ARGS_RULES).each do |part|
        part = part.strip
        if m = part.match(NAMED_ARG_RE)
          named[m[1]] = m[2].strip
        elsif !part.empty?
          positional << part
        end
      end
      {named, positional}
    end

    # Yields each `new Kind(args)` of an `operations: [...]` list with its
    # offset into that list (keyed `'name' => new Get()` lists included).
    private def each_operation(list : String, &)
      return unless list.starts_with?('[') && list.ends_with?(']')

      offset = 1
      Noir::TopLevelSplit.split(list[1...-1], ',', ARGS_RULES).each do |part|
        stripped = part.lstrip
        if m = stripped.match(NEW_RE)
          args = m[2]? ? stripped[m.end(0)...(stripped.rindex(')') || stripped.size)] : ""
          yield m[1], args, offset + part.size - stripped.size
        end
        offset += part.size + 1
      end
    end

    # `parameters: ['q' => new QueryParameter(key: 'search'), …]`
    private def parameters(list : String?) : Array(Param)
      params = [] of Param
      return params unless list && list.starts_with?('[') && list.ends_with?(']')

      Noir::TopLevelSplit.split(list[1...-1], ',', ARGS_RULES).each do |part|
        next unless m = part.strip.match(/\A['"]([^'"]+)['"]\s*=>\s*new\s+\\?(?:[\w\\]+\\)?(\w+)\s*(?:\((.*)\))?\s*\z/m)
        type = PARAMETER_TYPES[m[2]]?
        next unless type
        named, positional = split_args(m[3]? || "")
        name = literal(named["key"]? || positional.first?) || m[1]
        params << Param.new(name, "", type)
      end
      params
    end

    private def literal(value : String?) : String?
      return unless value
      value.match(STRING_RE).try(&.[2])
    end

    # API Platform's default UnderscorePathSegmentNameGenerator: Doctrine's
    # tableize (`BookReview` -> `book_review`), then pluralize.
    # ponytail: regular English plurals only; Doctrine's irregular table
    # (person → people, index → indices) and uncountables are not mirrored.
    private def segment(short_name : String) : String
      name = short_name.gsub(/(?<=\w)([A-Z])/, "_\\1").downcase
      case name
      when /[^aeiou]y\z/       then name[0...-1] + "ies"
      when /(?:s|x|z|ch|sh)\z/ then name + "es"
      else                          name + "s"
      end
    end

    # App root (the directory holding `config/`) → API Platform route prefix.
    private def route_prefixes : Hash(String, Prefix)
      prefixes = {} of String => Prefix
      # Laravel's packaged config defaults `route_prefix` to `/api`; a
      # published config/api-platform.php below overrides it.
      get_files_by_extension(".json").each do |path|
        next unless path.ends_with?("/composer.json")
        prefixes[File.dirname(path)] = Prefix.new("/api", true) if read_file_content(path).includes?(%("api-platform/laravel"))
      end
      get_files_by_extensions([".yaml", ".yml"]).each do |path|
        next unless path.includes?("/config/routes")
        content = read_file_content(path)
        next unless content.includes?("api_platform")
        YAML.parse(content).as_h?.try &.each_value do |route|
          route = route.as_h? || next
          next unless route[YAML::Any.new("type")]?.try(&.as_s?) == "api_platform"
          prefixes[app_root(path)] = Prefix.new(route[YAML::Any.new("prefix")]?.try(&.as_s?) || "", false)
        end
      rescue e
        logger.debug "Error parsing API Platform routes in #{path}: #{e}"
      end
      get_files_by_extension(".php").each do |path|
        next unless path.ends_with?("/config/api-platform.php")
        if m = read_file_content(path).match(/^\s*['"]route_prefix['"]\s*=>\s*['"]([^'"]*)['"]/m)
          prefixes[app_root(path)] = Prefix.new(m[1], true)
        end
      end
      prefixes
    end

    private def app_root(config_path : String) : String
      config_path[0, config_path.rindex("/config/") || 0]
    end

    private def prefix_for(path : String) : Prefix
      root = @prefixes.keys.select { |r| path.starts_with?("#{r}/") }.max_by?(&.size)
      root ? @prefixes[root] : Prefix.new("", false)
    end
  end
end
