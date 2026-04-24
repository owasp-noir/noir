require "../../../models/analyzer"
require "../../../ext/tree_sitter/tree_sitter"

module Analyzer::Java
  class Armeria < Analyzer
    REGEX_SERVER_CODE_BLOCK = /Server\s*\.builder\(\s*\)\s*\.[^;]*build\(\)\s*\./
    REGEX_SERVICE_CODE      = /\.service(If|Under|)?\([^;]+?\)/
    REGEX_ROUTE_CODE        = /\.route\(\)\s*\.\s*(\w+)\s*\(([^\.]*)\)\./

    # HTTP method annotation names supported by Armeria's annotated
    # service style. Simple names — fully-qualified forms like
    # `@com.linecorp.armeria.server.annotation.Get` are normalised to
    # the last segment before lookup.
    HTTP_METHOD_ANNOTATIONS = ["Get", "Post", "Put", "Delete", "Patch", "Head", "Options", "Trace"]

    def analyze
      # Source Analysis
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
                    content = File.read(path, encoding: "utf-8", invalid: :skip)

                    # Annotation-based services (`@Get("/x")` etc.) —
                    # Kotlin files reach here too, but tree-sitter-java
                    # doesn't parse Kotlin cleanly, so skip non-Java.
                    if content.includes?("com.linecorp.armeria.server.annotation.") && path.ends_with?(".java")
                      analyze_annotated_service(path, content)
                    end

                    # Server.builder()-style routes (regex-scoped — the
                    # builder chain isn't worth a dedicated TS walk yet).
                    details = Details.new(PathInfo.new(path))
                    content.scan(REGEX_SERVER_CODE_BLOCK) do |server_codeblock_match|
                      server_codeblock = server_codeblock_match[0]

                      server_codeblock.scan(REGEX_SERVICE_CODE) do |service_code_match|
                        next if service_code_match.size != 2
                        endpoint_param_index = 0
                        if service_code_match[1] == "If"
                          endpoint_param_index = 1
                        end

                        service_code = service_code_match[0]
                        args = service_code.split(",")
                        if args.size > endpoint_param_index
                          raw_endpoint = args[endpoint_param_index]
                          endpoint = raw_endpoint.split("(")[-1].gsub("\"", "").strip
                          if endpoint.starts_with?("/")
                            @result << Endpoint.new(endpoint, "GET", details)
                          end
                        end
                      end

                      server_codeblock.scan(REGEX_ROUTE_CODE) do |route_code_match|
                        next if route_code_match.size != 3
                        http_method = route_code_match[1].upcase
                        raw_endpoint = route_code_match[2]
                        endpoint = raw_endpoint.split("\"")[-2] if raw_endpoint.includes?("\"")
                        if endpoint && endpoint.starts_with?("/")
                          @result << Endpoint.new(endpoint, http_method, details)
                        end
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      @result
    end

    # ---- annotation-based service routes ------------------------------

    private def analyze_annotated_service(path : String, content : String)
      Noir::TreeSitter.parse_java(content) do |root|
        walk_class_containers(root) do |cls|
          cls_body = Noir::TreeSitter.field(cls, "body")
          next unless cls_body
          Noir::TreeSitter.each_named_child(cls_body) do |member|
            next unless Noir::TreeSitter.node_type(member) == "method_declaration"
            handle_method(member, content, path)
          end
        end
      end
    end

    private def walk_class_containers(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration"
        block.call(node)
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_class_containers(child, &block)
      end
    end

    private def handle_method(method : LibTreeSitter::TSNode, content : String, path : String)
      mods = find_modifiers(method)
      return unless mods

      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        name_node = Noir::TreeSitter.field(ann, "name")
        next unless name_node
        ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name_node, content))
        next unless HTTP_METHOD_ANNOTATIONS.includes?(ann_name)

        url_path = extract_url_from_annotation(ann, content)
        next if url_path.empty?

        http_method = ann_name.upcase
        line = Noir::TreeSitter.node_start_row(ann) + 1
        details = Details.new(PathInfo.new(path, line))

        parameters = collect_method_params(method, content, url_path)
        endpoint = Endpoint.new(url_path, http_method, parameters, details)
        extract_path_parameters(url_path, endpoint)
        @result << endpoint
      end
    end

    private def find_modifiers(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "modifiers"
      end
      nil
    end

    private def simple_annotation_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    # Extract the path from `@Get("/x")` or `@Get(value = "/x")`. Returns
    # "" when the annotation has no string literal argument.
    private def extract_url_from_annotation(ann : LibTreeSitter::TSNode, content : String) : String
      args = Noir::TreeSitter.field(ann, "arguments")
      return "" unless args
      result = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal"
          result = decode_string_literal(arg, content)
          break unless result.empty?
        when "element_value_pair"
          val = Noir::TreeSitter.field(arg, "value")
          if val && Noir::TreeSitter.node_type(val) == "string_literal"
            result = decode_string_literal(val, content)
            break unless result.empty?
          end
        end
      end
      result
    end

    # Walk method formal_parameters, translating Armeria's annotation
    # set into `Param`s:
    #
    #   - `@Param("name")` — query parameter (unless the name matches a
    #     `{template}` variable in the URL, in which case it's a path
    #     parameter and surfaces later through `extract_path_parameters`)
    #   - `@Header("Name")` — header parameter
    #   - `@RequestObject` — JSON body; parameter name taken from the
    #     declared variable name
    private def collect_method_params(method : LibTreeSitter::TSNode, content : String, url_path : String) : Array(Param)
      params = [] of Param
      fparams = Noir::TreeSitter.field(method, "parameters")
      return params unless fparams

      path_param_names = Set(String).new
      url_path.scan(/\{(\w+)\}/) do |match|
        path_param_names << match[1] if match.size > 1
      end

      Noir::TreeSitter.each_named_child(fparams) do |fp|
        next unless Noir::TreeSitter.node_type(fp) == "formal_parameter"
        name_node = Noir::TreeSitter.field(fp, "name")
        next unless name_node
        arg_name = Noir::TreeSitter.node_text(name_node, content)

        param_mods = find_modifiers(fp)
        next unless param_mods

        Noir::TreeSitter.each_named_child(param_mods) do |pa|
          pa_ty = Noir::TreeSitter.node_type(pa)
          next unless pa_ty == "annotation" || pa_ty == "marker_annotation"
          name = Noir::TreeSitter.field(pa, "name")
          next unless name
          ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name, content))

          case ann_name
          when "Param"
            param_name = extract_annotation_string_arg(pa, content) || arg_name
            # Path params are emitted later by `extract_path_parameters`;
            # skip here to avoid duplicates.
            next if path_param_names.includes?(param_name)
            params << Param.new(param_name, "", "query")
          when "Header"
            param_name = extract_annotation_string_arg(pa, content) || arg_name
            params << Param.new(param_name, "", "header")
          when "RequestObject"
            params << Param.new(arg_name, "", "json")
          end
        end
      end

      params
    end

    private def extract_annotation_string_arg(ann : LibTreeSitter::TSNode, content : String) : String?
      args = Noir::TreeSitter.field(ann, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal"
          return decode_string_literal(arg, content)
        when "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key")
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          k = Noir::TreeSitter.node_text(key, content)
          next unless k == "value" || k == "name"
          if Noir::TreeSitter.node_type(val) == "string_literal"
            return decode_string_literal(val, content)
          end
        end
      end
      nil
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, content : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, content)
          end
        end
      end
      buf
    end

    # Extract path parameters from URLs like /users/{userId} or /items/{itemId}/comments
    private def extract_path_parameters(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) do |match|
        if match.size > 0
          param_name = match[1]
          # Only add if not already present
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
      end
    end
  end
end
