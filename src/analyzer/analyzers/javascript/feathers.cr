require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/import_graph"
require "../../../utils/url_path"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/extraction_result_cache"

module Analyzer::Javascript
  # Feathers.js (https://feathersjs.com) is service-based rather than
  # route-based: registering a service at a path auto-generates REST
  # verbs from whichever of the standard CRUD methods the service
  # implements.
  #
  #     app.use('/messages', new MessageService())
  #     app.service('messages').hooks({ ... })
  #
  #   find(params)          -> GET    /messages
  #   get(id, params)       -> GET    /messages/:id
  #   create(data, params)  -> POST   /messages
  #   update(id, data, params) -> PUT /messages/:id
  #   patch(id, data, params)  -> PATCH /messages/:id
  #   remove(id, params)    -> DELETE /messages/:id
  #
  # `app.use(path, service, options)` accepts an optional third
  # argument whose `methods:` array is the *authoritative* list of
  # externally exposed methods when present (v5 "Dove" API) — it is
  # honoured here as an intersection against whatever methods were
  # otherwise detected/assumed. The `path` and `methods:` value are
  # both frequently bare identifiers pointing at a sibling
  # `<name>.shared.ts` module in the current (v5/"Dove") CLI generator
  # layout (`export const messagePath = 'messages'`, `export const
  # messageMethods = ['find', 'get', ...] as const`) rather than
  # inline literals — both are resolved the same one-`import`-hop way
  # as the service class itself.
  class Feathers < JavascriptEngine
    analyzer_for "js_feathers"

    JS_EXTENSIONS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx"]

    CRUD_METHODS = %w[find get create update patch remove]

    # method name => {HTTP verb, needs a trailing /:id segment}
    CRUD_VERB = {
      "find"   => {"GET", false},
      "get"    => {"GET", true},
      "create" => {"POST", false},
      "update" => {"PUT", true},
      "patch"  => {"PATCH", true},
      "remove" => {"DELETE", true},
    }

    BODY_METHODS = Set{"create", "update", "patch"}

    # The officially documented Feathers database-adapter service base
    # classes (https://feathersjs.com/api/databases/adapters) — every
    # one of these implements the full CRUD set itself, so a subclass
    # that overrides none (or only some) of them still exposes all six
    # externally, unless narrowed by an explicit `methods:` option.
    KNOWN_ADAPTER_BASE_CLASSES = Set{
      "Service", "AdapterService",
      "KnexService", "MongoDBService", "MemoryService", "SequelizeService",
      "NeDBService", "MikroOrmService", "ObjectionService", "PrismaService",
      "RethinkDBService", "MongooseService", "FeathersSequelize",
    }

    USE_CALL_RE = /\.use\s*\(/

    QUERY_PARAM_RE       = /\bparams\.query\.(\w+)|\bparams\.query\[\s*['"](\w+)['"]\s*\]/
    QUERY_DESTRUCTURE_RE = /(?:const|let|var)\s*\{\s*([^}]+)\}\s*=\s*params\.query\b/
    HEADER_PARAM_RE      = /\bparams\.headers\.(\w+)|\bparams\.headers\[\s*['"]([\w-]+)['"]\s*\]/

    record FeathersMethodInfo,
      params : Array(Param),
      callees : Array(Noir::JSCalleeExtractor::Entry)

    record FeathersServiceDef,
      adapter_backed : Bool,
      methods : Hash(String, FeathersMethodInfo)

    record FeathersUseCall,
      path_arg : String,
      path_is_literal : Bool,
      service_node_type : Symbol, # :new_class, :object, :identifier
      service_name : String,      # class_name or identifier name or ""
      inline_service : FeathersServiceDef?,
      methods_option : Set(String)?,
      methods_option_ident : String?,
      line : Int32

    record FeathersFileFacts,
      classes : Hash(String, FeathersServiceDef),
      named_objects : Hash(String, FeathersServiceDef),
      default_export_object : FeathersServiceDef?,
      sole_class : FeathersServiceDef?,
      string_constants : Hash(String, String),
      array_constants : Hash(String, Set(String)),
      local_instances : Hash(String, String),
      router_factories : Set(String),
      service_calls : Set(String),
      imports : Hash(String, Tuple(String, String)),
      use_calls : Array(FeathersUseCall)

    @@memo = Hash(UInt64, FeathersFileFacts).new
    @@memo_mutex = Mutex.new

    Noir::ExtractionResultCache.register_clearer do
      @@memo_mutex.synchronize { @@memo.clear }
    end

    private def feathers_file_facts(path : String, content : String, include_callee : Bool) : FeathersFileFacts
      key = Noir::ExtractionResultCache.key(content, "feathers_facts", path, include_callee ? "1" : "0")
      Noir::ExtractionResultCache.fetch(@@memo, key, @@memo_mutex) do
        extract_feathers_facts(path, content, include_callee)
      end
    end

    def analyze
      result = [] of Endpoint
      include_callee = callees_needed?

      parallel_file_scan(JS_EXTENSIONS) do |path|
        content = read_file_content(path)
        next unless content.matches?(USE_CALL_RE)

        facts = feathers_file_facts(path, content, include_callee)
        next if facts.use_calls.empty?

        facts.use_calls.each do |call|
          process_use_call(path, call, facts, result, include_callee)
        end
      end

      result
    end

    private def process_use_call(path : String, call : FeathersUseCall, facts : FeathersFileFacts,
                                 result : Array(Endpoint), include_callee : Bool)
      service_path =
        if call.path_is_literal
          call.path_arg
        else
          resolve_path_literal(path, call.path_arg, facts, include_callee)
        end
      return unless service_path

      methods, service_def = resolve_service_methods(path, call, facts, service_path, include_callee)
      return if methods.nil? || methods.empty?

      if opts_methods = call.methods_option
        methods = methods & opts_methods
      elsif opt_ident = call.methods_option_ident
        if resolved_opts = resolve_methods_option(path, opt_ident, facts, include_callee)
          methods = methods & resolved_opts
        end
      end
      return if methods.empty?

      emit_service_endpoints(result, path, service_path, methods, service_def, call.line)
    end

    private def resolve_service_methods(path : String, call : FeathersUseCall, facts : FeathersFileFacts,
                                        service_path : String, include_callee : Bool) : Tuple(Set(String)?, FeathersServiceDef?)
      case call.service_node_type
      when :new_class
        class_name = call.service_name
        if service = resolve_class_definition(path, class_name, facts, include_callee)
          methods = service.adapter_backed ? Set(String).new(CRUD_METHODS) : service.methods.keys.to_set
          return {methods, service}
        end
        {Set(String).new(CRUD_METHODS), nil}
      when :object
        if service = call.inline_service
          methods = service.methods.keys.to_set
          return {methods, service}
        end
        {nil, nil}
      when :identifier
        name = call.service_name
        return {nil, nil} if facts.router_factories.includes?(name)

        if class_name = facts.local_instances[name]?
          if service = resolve_class_definition(path, class_name, facts, include_callee)
            methods = service.adapter_backed ? Set(String).new(CRUD_METHODS) : service.methods.keys.to_set
            return {methods, service}
          end
          return {Set(String).new(CRUD_METHODS), nil}
        end

        if service = resolve_service_definition(path, name, facts, include_callee)
          methods = service.adapter_backed ? Set(String).new(CRUD_METHODS) : service.methods.keys.to_set
          return {methods, service}
        end

        if service_call_co_occurs?(facts, service_path, call.path_arg)
          return {Set(String).new(CRUD_METHODS), nil}
        end

        {nil, nil}
      else
        {nil, nil}
      end
    end

    private def resolve_class_definition(path : String, class_name : String, facts : FeathersFileFacts, include_callee : Bool) : FeathersServiceDef?
      if cls = facts.classes[class_name]?
        return cls
      end

      if imp = facts.imports[class_name]?
        spec, exported_name = imp
        resolved_path = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: import_boundary_for(path))
        if resolved_path
          begin
            resolved_content = read_file_content(resolved_path)
            target_facts = feathers_file_facts(resolved_path, resolved_content, include_callee)
            return target_facts.classes[exported_name]? || target_facts.sole_class || target_facts.default_export_object
          rescue
          end
        end
      end

      nil
    end

    private def resolve_service_definition(path : String, name : String, facts : FeathersFileFacts, include_callee : Bool) : FeathersServiceDef?
      if service = facts.classes[name]?
        return service
      end
      if service = facts.named_objects[name]?
        return service
      end

      if imp = facts.imports[name]?
        spec, exported_name = imp
        resolved_path = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: import_boundary_for(path))
        if resolved_path
          begin
            resolved_content = read_file_content(resolved_path)
            target_facts = feathers_file_facts(resolved_path, resolved_content, include_callee)
            return target_facts.classes[exported_name]? ||
              target_facts.sole_class ||
              target_facts.named_objects[exported_name]? ||
              target_facts.default_export_object
          rescue
          end
        end
      end

      nil
    end

    private def resolve_path_literal(path : String, name : String, facts : FeathersFileFacts, include_callee : Bool) : String?
      if s = facts.string_constants[name]?
        return s
      end

      if imp = facts.imports[name]?
        spec, exported_name = imp
        resolved_path = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: import_boundary_for(path))
        if resolved_path
          begin
            resolved_content = read_file_content(resolved_path)
            target_facts = feathers_file_facts(resolved_path, resolved_content, include_callee)
            return target_facts.string_constants[exported_name]?
          rescue
          end
        end
      end

      nil
    end

    private def resolve_methods_option(path : String, name : String, facts : FeathersFileFacts, include_callee : Bool) : Set(String)?
      if mset = facts.array_constants[name]?
        return mset
      end

      if imp = facts.imports[name]?
        spec, exported_name = imp
        resolved_path = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: import_boundary_for(path))
        if resolved_path
          begin
            resolved_content = read_file_content(resolved_path)
            target_facts = feathers_file_facts(resolved_path, resolved_content, include_callee)
            return target_facts.array_constants[exported_name]?
          rescue
          end
        end
      end

      nil
    end

    private def service_call_co_occurs?(facts : FeathersFileFacts, service_path : String, raw_path_arg : String) : Bool
      normalized = service_path.lstrip('/')
      candidates = Set{service_path, normalized, "/#{normalized}"}
      return true if candidates.any? { |c| facts.service_calls.includes?(c) }

      raw = raw_path_arg.strip
      return false if raw.empty?
      facts.service_calls.includes?(raw)
    end

    private def emit_service_endpoints(result : Array(Endpoint), path : String, service_path : String,
                                       methods : Set(String), service : FeathersServiceDef?,
                                       line : Int32)
      base_url = normalize_service_path(service_path)

      CRUD_METHODS.each do |crud_method|
        next unless methods.includes?(crud_method)
        verb, needs_id = CRUD_VERB[crud_method]
        url = needs_id ? Noir::URLPath.join_trimmed(base_url, ":id") : base_url

        endpoint = Endpoint.new(url, verb, Details.new(PathInfo.new(path, line)))

        url.scan(/:(\w+)/) do |pm|
          endpoint.push_param(Param.new(pm[1], "", "path")) if pm.size > 0
        end
        endpoint.push_param(Param.new("body", "", "json")) if BODY_METHODS.includes?(crud_method)

        if service && (method_info = service.methods[crud_method]?)
          method_info.params.each do |p|
            endpoint.push_param(p)
          end
          attach_js_callees(endpoint, method_info.callees)
        end

        result << endpoint
      end
    end

    private def normalize_service_path(service_path : String) : String
      trimmed = service_path.strip
      return "/" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def extract_feathers_facts(path : String, source : String, include_callees : Bool) : FeathersFileFacts
      classes = Hash(String, FeathersServiceDef).new
      named_objects = Hash(String, FeathersServiceDef).new
      default_export_object = nil.as(FeathersServiceDef?)
      string_constants = Hash(String, String).new
      array_constants = Hash(String, Set(String)).new
      local_instances = Hash(String, String).new
      router_factories = Set(String).new
      service_calls = Set(String).new
      imports = Hash(String, Tuple(String, String)).new
      use_calls = [] of FeathersUseCall
      default_export_name = nil.as(String?)

      Noir::TreeSitter.parse_js_family(source, path) do |root|
        Noir::TreeSitter.walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "class_declaration"
            if cd_name = Noir::TreeSitter.field(node, "name")
              name = Noir::TreeSitter.node_text(cd_name, source)
              classes[name] = extract_service_def_from_class(node, source, path, include_callees)
            end
          when "export_statement"
            if decl = Noir::TreeSitter.field(node, "declaration")
              decl_unwrapped = Noir::TreeSitter.unwrap_expression(decl)
              if Noir::TreeSitter.node_type(decl_unwrapped) == "class_declaration"
                cls = extract_service_def_from_class(decl_unwrapped, source, path, include_callees)
                if exp_cd_name = Noir::TreeSitter.field(decl_unwrapped, "name")
                  classes[Noir::TreeSitter.node_text(exp_cd_name, source)] = cls
                end
              end
            elsif val = Noir::TreeSitter.field(node, "value")
              val_unwrapped = Noir::TreeSitter.unwrap_expression(val)
              case Noir::TreeSitter.node_type(val_unwrapped)
              when "object"
                default_export_object = extract_service_def_from_object(val_unwrapped, source, path, include_callees)
              when "class"
                cls = extract_service_def_from_class(val_unwrapped, source, path, include_callees)
                classes["default"] = cls
                if val_cd_name = Noir::TreeSitter.field(val_unwrapped, "name")
                  classes[Noir::TreeSitter.node_text(val_cd_name, source)] = cls
                end
              when "identifier"
                default_export_name = Noir::TreeSitter.node_text(val_unwrapped, source)
              end
            end
          when "variable_declarator"
            vd_name = Noir::TreeSitter.field(node, "name")
            vd_val = Noir::TreeSitter.field(node, "value")
            if vd_name && vd_val
              if Noir::TreeSitter.node_type(vd_name) == "identifier"
                name = Noir::TreeSitter.node_text(vd_name, source)
                val = Noir::TreeSitter.unwrap_expression(vd_val)
                case Noir::TreeSitter.node_type(val)
                when "class"
                  classes[name] = extract_service_def_from_class(val, source, path, include_callees)
                when "object"
                  named_objects[name] = extract_service_def_from_object(val, source, path, include_callees)
                when "new_expression"
                  if ctor = Noir::TreeSitter.field(val, "constructor")
                    ctor_unwrapped = Noir::TreeSitter.unwrap_expression(ctor)
                    if Noir::TreeSitter.node_type(ctor_unwrapped) == "identifier"
                      local_instances[name] = Noir::TreeSitter.node_text(ctor_unwrapped, source)
                    end
                  end
                when "string", "template_string"
                  if s = decode_string(val, source)
                    string_constants[name] = s
                  end
                when "array"
                  mset = Set(String).new
                  Noir::TreeSitter.each_named_arg(val) do |elem|
                    if s = decode_string(Noir::TreeSitter.unwrap_expression(elem), source)
                      mset << s.downcase if CRUD_METHODS.includes?(s.downcase)
                    end
                  end
                  array_constants[name] = mset
                when "call_expression"
                  if fn = Noir::TreeSitter.field(val, "function")
                    fn_unwrapped = Noir::TreeSitter.unwrap_expression(fn)
                    fn_text = Noir::TreeSitter.node_text(fn_unwrapped, source)
                    if fn_text == "express.Router" || fn_text == "Router"
                      router_factories << name
                    elsif fn_text == "require"
                      if args_node = Noir::TreeSitter.field(val, "arguments")
                        if arg0 = Noir::TreeSitter.first_named_arg(args_node)
                          if spec = decode_string(arg0, source)
                            imports[name] = {spec, "default"}
                          end
                        end
                      end
                    end
                  end
                end
              elsif Noir::TreeSitter.node_type(vd_name) == "object_pattern"
                val = Noir::TreeSitter.unwrap_expression(vd_val)
                if Noir::TreeSitter.node_type(val) == "call_expression"
                  if fn = Noir::TreeSitter.field(val, "function")
                    if Noir::TreeSitter.node_text(Noir::TreeSitter.unwrap_expression(fn), source) == "require"
                      if args_node = Noir::TreeSitter.field(val, "arguments")
                        if arg0 = Noir::TreeSitter.first_named_arg(args_node)
                          if spec = decode_string(arg0, source)
                            Noir::TreeSitter.each_named_child(vd_name) do |prop|
                              case Noir::TreeSitter.node_type(prop)
                              when "shorthand_property_identifier_pattern"
                                loc_name = Noir::TreeSitter.node_text(prop, source)
                                imports[loc_name] = {spec, loc_name}
                              when "pair_pattern"
                                pat_k = Noir::TreeSitter.field(prop, "key")
                                pat_v = Noir::TreeSitter.field(prop, "value")
                                if pat_k && pat_v
                                  exp_name = Noir::TreeSitter.node_text(pat_k, source)
                                  loc_name = Noir::TreeSitter.node_text(pat_v, source)
                                  imports[loc_name] = {spec, exp_name}
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          when "assignment_expression"
            left = Noir::TreeSitter.field(node, "left")
            right = Noir::TreeSitter.field(node, "right")
            if left && right
              left_text = Noir::TreeSitter.node_text(Noir::TreeSitter.unwrap_expression(left), source)
              right_unwrapped = Noir::TreeSitter.unwrap_expression(right)
              if left_text == "module.exports"
                case Noir::TreeSitter.node_type(right_unwrapped)
                when "object"
                  default_export_object = extract_service_def_from_object(right_unwrapped, source, path, include_callees)
                when "class"
                  cls = extract_service_def_from_class(right_unwrapped, source, path, include_callees)
                  classes["default"] = cls
                  if asgn_cd_name = Noir::TreeSitter.field(right_unwrapped, "name")
                    classes[Noir::TreeSitter.node_text(asgn_cd_name, source)] = cls
                  end
                when "identifier"
                  default_export_name = Noir::TreeSitter.node_text(right_unwrapped, source)
                end
              elsif left_text.starts_with?("exports.")
                exp_name = left_text[8..]
                case Noir::TreeSitter.node_type(right_unwrapped)
                when "class"
                  cls = extract_service_def_from_class(right_unwrapped, source, path, include_callees)
                  classes[exp_name] = cls
                when "object"
                  named_objects[exp_name] = extract_service_def_from_object(right_unwrapped, source, path, include_callees)
                end
              end
            end
          when "import_statement"
            if src_node = Noir::TreeSitter.field(node, "source")
              if spec = decode_string(src_node, source)
                Noir::TreeSitter.walk(node) do |child|
                  case Noir::TreeSitter.node_type(child)
                  when "import_specifier"
                    imp_name = Noir::TreeSitter.field(child, "name")
                    imp_alias = Noir::TreeSitter.field(child, "alias")
                    if imp_name
                      exp_name = Noir::TreeSitter.node_text(imp_name, source)
                      loc_name = imp_alias ? Noir::TreeSitter.node_text(imp_alias, source) : exp_name
                      imports[loc_name] = {spec, exp_name}
                    end
                  when "import_clause"
                    Noir::TreeSitter.each_named_child(child) do |c|
                      if Noir::TreeSitter.node_type(c) == "identifier"
                        loc_name = Noir::TreeSitter.node_text(c, source)
                        imports[loc_name] = {spec, "default"}
                      end
                    end
                  end
                end
              end
            end
          when "call_expression"
            callee = Noir::TreeSitter.field(node, "function")
            if callee
              callee_unwrapped = Noir::TreeSitter.unwrap_expression(callee)
              if Noir::TreeSitter.node_type(callee_unwrapped) == "member_expression"
                prop = Noir::TreeSitter.field(callee_unwrapped, "property")
                prop_name = property_key_name(prop, source)

                if prop_name == "service"
                  if args_node = Noir::TreeSitter.field(node, "arguments")
                    if arg0 = Noir::TreeSitter.first_named_arg(args_node)
                      arg0_unwrapped = Noir::TreeSitter.unwrap_expression(arg0)
                      case Noir::TreeSitter.node_type(arg0_unwrapped)
                      when "string", "template_string"
                        if s = decode_string(arg0_unwrapped, source)
                          service_calls << s
                          service_calls << s.lstrip('/')
                          service_calls << "/#{s.lstrip('/')}"
                        end
                      when "identifier"
                        service_calls << Noir::TreeSitter.node_text(arg0_unwrapped, source)
                      end
                    end
                  end
                elsif prop_name == "use"
                  if args_node = Noir::TreeSitter.field(node, "arguments")
                    args = [] of LibTreeSitter::TSNode
                    Noir::TreeSitter.each_named_arg(args_node) { |a| args << a }
                    if args.size >= 2
                      arg0 = Noir::TreeSitter.unwrap_expression(args[0])
                      path_str = decode_string(arg0, source)
                      path_arg = ""
                      path_is_literal = false
                      if path_str
                        path_arg = path_str
                        path_is_literal = true
                      elsif Noir::TreeSitter.node_type(arg0) == "identifier"
                        path_arg = Noir::TreeSitter.node_text(arg0, source)
                        path_is_literal = false
                      end

                      unless path_arg.empty?
                        arg1 = Noir::TreeSitter.unwrap_expression(args[1])
                        service_type = :unknown
                        service_name = ""
                        inline_service = nil.as(FeathersServiceDef?)

                        case Noir::TreeSitter.node_type(arg1)
                        when "new_expression"
                          service_type = :new_class
                          if ctor = Noir::TreeSitter.field(arg1, "constructor")
                            ctor_unwrapped = Noir::TreeSitter.unwrap_expression(ctor)
                            if Noir::TreeSitter.node_type(ctor_unwrapped) == "identifier"
                              service_name = Noir::TreeSitter.node_text(ctor_unwrapped, source)
                            end
                          end
                        when "object"
                          service_type = :object
                          inline_service = extract_service_def_from_object(arg1, source, path, include_callees)
                        when "identifier"
                          service_type = :identifier
                          service_name = Noir::TreeSitter.node_text(arg1, source)
                        end

                        unless service_type == :unknown
                          methods_option = nil.as(Set(String)?)
                          methods_option_ident = nil.as(String?)

                          if args.size >= 3
                            arg2 = Noir::TreeSitter.unwrap_expression(args[2])
                            if Noir::TreeSitter.node_type(arg2) == "object"
                              if methods_val = extract_prop_value(arg2, "methods", source)
                                val_unwrapped = Noir::TreeSitter.unwrap_expression(methods_val)
                                if Noir::TreeSitter.node_type(val_unwrapped) == "array"
                                  mset = Set(String).new
                                  Noir::TreeSitter.each_named_arg(val_unwrapped) do |elem|
                                    if s = decode_string(Noir::TreeSitter.unwrap_expression(elem), source)
                                      mset << s.downcase if CRUD_METHODS.includes?(s.downcase)
                                    end
                                  end
                                  methods_option = mset
                                elsif Noir::TreeSitter.node_type(val_unwrapped) == "identifier"
                                  methods_option_ident = Noir::TreeSitter.node_text(val_unwrapped, source)
                                end
                              end
                            end
                          end

                          line = Noir::TreeSitter.node_start_row(node) + 1
                          use_calls << FeathersUseCall.new(
                            path_arg, path_is_literal, service_type, service_name,
                            inline_service, methods_option, methods_option_ident, line
                          )
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      if def_name = default_export_name
        if cls = classes[def_name]?
          classes["default"] = cls
        end
      end

      sole_class = classes.size == 1 ? classes.values.first : nil

      FeathersFileFacts.new(
        classes, named_objects, default_export_object, sole_class,
        string_constants, array_constants, local_instances,
        router_factories, service_calls, imports, use_calls
      )
    end

    private def extract_service_def_from_class(node : LibTreeSitter::TSNode, source : String,
                                               path : String, include_callees : Bool) : FeathersServiceDef
      adapter_backed = adapter_backed_class?(node, source)
      methods = Hash(String, FeathersMethodInfo).new

      if body_node = Noir::TreeSitter.field(node, "body")
        Noir::TreeSitter.each_named_child(body_node) do |child|
          if Noir::TreeSitter.node_type(child) == "method_definition"
            name_node = Noir::TreeSitter.field(child, "name")
            method_name = property_key_name(name_node, source)
            if CRUD_METHODS.includes?(method_name)
              m_body = Noir::TreeSitter.field(child, "body")
              body_text = m_body ? Noir::TreeSitter.node_text(m_body, source) : ""
              params = extract_method_params(body_text)
              callees = include_callees ? Noir::JSCalleeExtractor.callees_for_handler_node(child, source, path) : [] of Noir::JSCalleeExtractor::Entry
              methods[method_name] = FeathersMethodInfo.new(params, callees)
            end
          end
        end
      end

      FeathersServiceDef.new(adapter_backed, methods)
    end

    private def extract_service_def_from_object(node : LibTreeSitter::TSNode, source : String,
                                                path : String, include_callees : Bool) : FeathersServiceDef
      methods = Hash(String, FeathersMethodInfo).new

      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "method_definition"
          name_node = Noir::TreeSitter.field(child, "name")
          method_name = property_key_name(name_node, source)
          if CRUD_METHODS.includes?(method_name)
            m_body = Noir::TreeSitter.field(child, "body")
            body_text = m_body ? Noir::TreeSitter.node_text(m_body, source) : ""
            params = extract_method_params(body_text)
            callees = include_callees ? Noir::JSCalleeExtractor.callees_for_handler_node(child, source, path) : [] of Noir::JSCalleeExtractor::Entry
            methods[method_name] = FeathersMethodInfo.new(params, callees)
          end
        when "pair"
          key_node = Noir::TreeSitter.field(child, "key")
          method_name = property_key_name(key_node, source)
          if CRUD_METHODS.includes?(method_name)
            if val_node = Noir::TreeSitter.field(child, "value")
              unwrapped = Noir::TreeSitter.unwrap_expression(val_node)
              case Noir::TreeSitter.node_type(unwrapped)
              when "arrow_function", "function_expression"
                m_body = Noir::TreeSitter.field(unwrapped, "body") || unwrapped
                body_text = Noir::TreeSitter.node_text(m_body, source)
                params = extract_method_params(body_text)
                callees = include_callees ? Noir::JSCalleeExtractor.callees_for_handler_node(unwrapped, source, path) : [] of Noir::JSCalleeExtractor::Entry
                methods[method_name] = FeathersMethodInfo.new(params, callees)
              else
                methods[method_name] = FeathersMethodInfo.new([] of Param, [] of Noir::JSCalleeExtractor::Entry)
              end
            end
          end
        end
      end

      FeathersServiceDef.new(false, methods)
    end

    private def adapter_backed_class?(node : LibTreeSitter::TSNode, source : String) : Bool
      heritage = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(node) do |child|
        if Noir::TreeSitter.node_type(child) == "class_heritage"
          heritage = child
          break
        end
      end
      return false unless heritage

      found = false
      Noir::TreeSitter.walk(heritage) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "type_identifier"
          name = Noir::TreeSitter.node_text(child, source)
          if KNOWN_ADAPTER_BASE_CLASSES.includes?(name)
            found = true
          end
        end
      end
      found
    end

    private def extract_method_params(body : String) : Array(Param)
      params = [] of Param
      body.scan(QUERY_PARAM_RE) do |m|
        name = (m[1]? || m[2]?).to_s
        params << Param.new(name, "", "query") unless name.empty?
      end
      body.scan(QUERY_DESTRUCTURE_RE) do |m|
        next unless m.size > 0
        (m[1]? || "").split(",").each do |raw|
          name = raw.split("=").first.strip.split(":").first.strip
          params << Param.new(name, "", "query") unless name.empty?
        end
      end
      body.scan(HEADER_PARAM_RE) do |m|
        name = (m[1]? || m[2]?).to_s
        params << Param.new(name, "", "header") unless name.empty?
      end
      params
    end
  end
end
