module Analyzer::Python
  # `path("tenants/<int:pk>/", include(get_model_urls("tenancy", "tenant")))`:
  # a urlconf entry mounting the url list a project function builds out of a
  # view registry, which decorators on the view classes fill at import time
  # (`@register_model_view(Tenant, "edit")`). Neither name means anything to
  # this code: the builder is recognised by its body (it subscripts a
  # module-level registry with its own parameters, filters the entries on
  # one, and makes a `path()` from another), the writer by appending a dict
  # to that same registry slot, and each decorator application is evaluated
  # against the writer's signature.
  class Django < PythonEngine
    alias PyValue = ::String | Bool?

    # The builder side: `registry['views'][app_label][model_name]` filtered
    # on `view['detail'] == detail`, routed by `config['path']`.
    private record RegistryReader, file : ::String, registry : ::String, keys : Array(::String),
      slot_params : Array(::String), params : Array(::String), defaults : Hash(::String, ::String),
      filter_key : ::String?, filter_param : ::String?, route_key : ::String, route_slash : Bool

    # One decorator application, evaluated: the slot it fills, the dict it
    # appends (values it could not evaluate left out), the view it decorates.
    private record RegistryEntry, slot : Array(PyValue), entry : Hash(::String, PyValue),
      file : ::String, view : ::String

    REGISTRY_INCLUDE_RE = /\A\s*include\s*\(\s*([A-Za-z_][\w.]*)\s*\(([\s\S]*)\)\s*\)\s*\z/
    REGISTRY_SLOT_RE    = /\b([A-Za-z_]\w*)((?:\[\s*['"]\w+['"]\s*\])+)((?:\[\s*[A-Za-z_]\w*\s*\])+)/
    REGISTRY_FILTER_RE  = /\[\s*['"](\w+)['"]\s*\]\s*==\s*([A-Za-z_]\w*)\b/
    REGISTRY_PATH_RE    = /(?<![\w.])path\s*\(\s*([^,()]+?)\s*,/
    DICT_KEY_RE         = /\[\s*['"](\w+)['"]\s*\]/

    @registry_readers = Hash(Tuple(::String, ::String), RegistryReader?).new
    @registry_entries = Hash(Tuple(::String, Array(::String), Int32), Array(RegistryEntry)).new

    # The endpoints the registry holds for the urlconf entry `view` mounted
    # at `url`; nil when `view` is no registry include or nothing fills it.
    private def registry_include_endpoints(urlconf : ::String, url : ::String, view : ::String) : Array(Endpoint)?
      return unless view.includes?("include")
      call = view.match(REGISTRY_INCLUDE_RE) || return
      site = resolve_python_class(urlconf, call[1]) || return
      reader = registry_reader(site[0], site[1]) || return
      args = bind_python_call(split_python_arguments(call[2]), reader.params, reader.defaults) || return
      values = (reader.slot_params + [reader.filter_param].compact).map { |param| python_literal(args[param]?.to_s) }
      return if values.any?(Symbol)
      slot = values[0, reader.slot_params.size].map(&.as(PyValue))
      filter = values[reader.slot_params.size]?

      matches = registry_entries(reader).select do |entry|
        next false unless entry.slot == slot
        key = reader.filter_key
        key.nil? || (entry.entry.has_key?(key) && entry.entry[key] == filter)
      end
      return if matches.empty?

      endpoints = [] of Endpoint
      matches.each do |entry|
        route = entry.entry[reader.route_key]?
        next unless route.is_a?(::String)
        route = "#{route}/" if reader.route_slash && !route.empty?
        extract_endpoints_from_file(join_url_parts(url, route), entry.file, entry.view).each { |endpoint| endpoints << endpoint }
      end
      endpoints
    end

    private def registry_reader(file : ::String, name : ::String) : RegistryReader?
      key = {file, name}
      return @registry_readers[key] if @registry_readers.has_key?(key)
      view_file = view_file_index(file)
      body = view_file.defs[name]?.try { |start| parse_code_block(view_file.tail(start)) }
      @registry_readers[key] = body ? read_registry_reader(file, body) : nil
    end

    private def read_registry_reader(file : ::String, body : ::String) : RegistryReader?
      params, defaults = python_signature(body)
      return if params.empty?
      code = body.lines.join('\n') { |line| strip_python_comment(line) }
      found = nil
      code.scan(REGISTRY_SLOT_RE) do |m|
        slot = m[3].scan(/[A-Za-z_]\w*/).map(&.[0])
        next unless slot.all?(&.in?(params))
        found = {m[1], m[2].scan(/['"](\w+)['"]/).map(&.[1]), slot}
        break
      end
      registry, keys, slot = found || return
      filter = code.scan(REGISTRY_FILTER_RE).find { |m| params.includes?(m[2]) }
      path_arg = code.match(REGISTRY_PATH_RE).try(&.[1].strip) || return
      route_expr = path_arg
      if path_arg.matches?(/\A[A-Za-z_]\w*\z/)
        route_expr = code.match(/^[ \t]*#{Regex.escape(path_arg)}[ \t]*=(?!=)([^\n]+)/m).try(&.[1]) || return
      end
      route_key = route_expr.match(DICT_KEY_RE).try(&.[1]) || return
      slash = route_expr.matches?(/\}\/['"]|\+\s*['"]\/['"]/)
      RegistryReader.new(file, registry, keys, slot, params, defaults, filter.try(&.[1]), filter.try(&.[2]), route_key, slash)
    end

    # Every decorator application that appends to `reader`'s registry slot.
    private def registry_entries(reader : RegistryReader) : Array(RegistryEntry)
      @registry_entries[{reader.registry, reader.keys, reader.slot_params.size}] ||= begin
        keys = reader.keys.join { |key| "\\[\\s*['\"]#{Regex.escape(key)}['\"]\\s*\\]" }
        slots = "\\[\\s*([A-Za-z_]\\w*(?:\\.\\w+)*)\\s*\\]" * reader.slot_params.size
        append_re = Regex.new("\\b#{Regex.escape(reader.registry)}#{keys}#{slots}\\.append\\s*\\(\\s*\\{")
        writers = [] of Tuple(::String, ::String)
        python_source_files.each do |file|
          content = read_file_content(file) rescue next
          next unless content.includes?(reader.registry) && content.includes?(".append(")
          next unless python_binding(file, reader.registry) == python_binding(reader.file, reader.registry)
          content.scan(append_re) do |m|
            factory = enclosing_top_level_def(content, m.begin(0)) || next
            writers << {file, factory}
          end
        end
        writers.uniq.flat_map { |file, factory| registry_factory_entries(file, factory, append_re) }
      end
    end

    # Where `name` as used in `file` is declared: the module it is imported
    # from, else `file` itself.
    private def python_binding(file : ::String, name : ::String) : Tuple(::String, ::String)
      symbols = @imported_symbols[file] ||= Noir::ImportGraph::Python.find_imported_symbols(@django_base_path, file, read_file_content(file))
      symbols[name]? || {file, name}
    end

    private def enclosing_top_level_def(content : ::String, offset : Int32) : ::String?
      content[0, offset].scan(/^(?:async[ \t]+)?def[ \t]+([A-Za-z_]\w*)[ \t]*\(/m).last?.try(&.[1])
    end

    # The registry entries each `@factory(...)` application in the project
    # appends, evaluated against `factory`'s signature.
    private def registry_factory_entries(file : ::String, factory : ::String, append_re : Regex) : Array(RegistryEntry)
      entries = [] of RegistryEntry
      view_file = view_file_index(file)
      start = view_file.defs[factory]? || return entries
      body = parse_code_block(view_file.tail(start)) || return entries
      params, defaults = python_signature(body)
      code = body.lines.join('\n') { |line| strip_python_comment(line) }
      append = code.match(append_re) || return entries
      # The class the inner wrapper receives: `def _wrapper(cls):`.
      wrapper_param = code[0, append.begin(0)].scan(/^[ \t]+(?:async[ \t]+)?def[ \t]+\w+[ \t]*\([ \t]*([A-Za-z_]\w*)/m).last?.try(&.[1]) || return entries
      open = append.end(0) - 1
      close = matching_brace(code, open) || return entries
      dict = Hash(::String, ::String).new
      split_python_arguments(code[(open + 1)...close]).each do |item|
        key, _, value = item.partition(':')
        name = Helper.extract_python_string(key.strip) || next
        dict[name] = value.gsub(/\s+/, " ").strip
      end
      return entries unless dict.values.includes?(wrapper_param)
      locals = Hash(::String, ::String).new
      code.scan(/^[ \t]+([A-Za-z_]\w*)[ \t]*=(?!=)[ \t]*([^\n]+)/m) { |m| locals[m[1]] ||= m[2].strip }
      slot_exprs = (1...append.size).map { |i| append[i] }
      decorator_re = /^\s*@(?:[\w.]+\.)?#{Regex.escape(factory)}\s*\(/

      python_source_files.each do |source|
        content = read_file_content(source) rescue next
        next unless content.includes?("@") && content.includes?(factory)
        lines = content.split('\n')
        lines.each_with_index do |line, index|
          next unless line.lstrip.starts_with?('@') && line.matches?(decorator_re)
          next unless source == file || resolve_python_class(source, line.lstrip[1..].partition('(')[0].strip) == {file, factory}
          call, _ = python_call_span(lines, index, line)
          arg_open = call.index('(') || next
          arg_close = call.rindex(')') || next
          args = bind_python_call(split_python_arguments(call[(arg_open + 1)...arg_close]), params, defaults) || next
          view = decorated_definition(lines, index) || next
          slot = slot_exprs.map { |expr| registry_slot_value(expr, locals, args, source) }
          next if slot.any?(Nil)
          env = Hash(::String, PyValue).new
          unknown = Set(::String).new
          args.each do |param, raw|
            value = python_literal(raw)
            value.is_a?(Symbol) ? unknown << param : (env[param] = value)
          end
          entry = Hash(::String, PyValue).new
          dict.each do |key, expr|
            next if expr == wrapper_param
            value = eval_python_expression(expr, env, unknown)
            entry[key] = value unless value.is_a?(Symbol)
          end
          entries << RegistryEntry.new(slot.map(&.as(PyValue)), entry, source, view)
        end
      end
      entries
    end

    # `model._meta.app_label` / `model._meta.model_name` (directly or
    # through a local) of the model class a decorator application passes.
    private def registry_slot_value(expr : ::String, locals : Hash(::String, ::String),
                                    args : Hash(::String, ::String), source : ::String) : ::String?
      expr = locals[expr]? || expr
      m = expr.match(/\A([A-Za-z_]\w*)\._meta\.(app_label|model_name)\z/) || return
      model = args[m[1]]? || return
      return unless model.matches?(/\A[A-Za-z_][\w.]*\z/)
      return model.rpartition('.')[2].downcase if m[2] == "model_name"
      site = resolve_python_class(source, model) || return
      django_app_label(site[0], site[1])
    end

    # Django's default `app_label`: the app package holding the models
    # module the class is declared in, unless its `Meta` names another.
    private def django_app_label(file : ::String, class_name : ::String) : ::String?
      if klass = drf_class_chain(file, class_name).first?
        if label = klass.codeblock.match(/^\s+app_label\s*=\s*['"](\w+)['"]/m)
          return label[1]
        end
      end
      parts = file.split('/')
      return parts[-2]? if parts.last == "models.py"
      index = parts[0...-1].rindex("models") || return
      index > 0 ? parts[index - 1] : nil
    end

    # The class or function the decorator stack starting at `index` decorates.
    private def decorated_definition(lines : Array(::String), index : Int32) : ::String?
      (index...Math.min(lines.size, index + 40)).each do |i|
        if m = lines[i].match(/^\s*(?:class|(?:async\s+)?def)\s+([A-Za-z_]\w*)/)
          return m[1]
        end
      end
      nil
    end

    # The source text a call's arguments bind to each parameter of a
    # signature, defaults filled in; nil when an argument has nowhere to go.
    private def bind_python_call(args : Array(::String), params : Array(::String),
                                 defaults : Hash(::String, ::String)) : Hash(::String, ::String)?
      bound = Hash(::String, ::String).new
      position = 0
      args.each do |arg|
        arg = arg.strip
        next if arg.empty?
        return if arg.starts_with?('*')
        if kw = arg.match(/\A([A-Za-z_]\w*)\s*=(?!=)\s*([\s\S]+)\z/)
          return unless params.includes?(kw[1])
          bound[kw[1]] = kw[2].strip
        else
          param = params[position]? || return
          bound[param] = arg
          position += 1
        end
      end
      params.each { |param| bound[param] = defaults[param] if !bound.has_key?(param) && defaults.has_key?(param) }
      bound
    end

    # A Python literal's value: a string, `True` / `False`, `None`, or
    # `:unknown` for anything else.
    private def python_literal(text : ::String) : PyValue | Symbol
      text = text.strip
      return true if text == "True"
      return false if text == "False"
      return if text == "None"
      if text.matches?(/\A[rRuU]?(['"])[^'"\\]*\1\z/)
        return text[(text.index(text[-1]) || 0) + 1...-1]
      end
      :unknown
    end

    # `path if path is not None else name`, `kwargs or {}`, a parameter, a
    # literal: the small expression language registry decorators use.
    private def eval_python_expression(expr : ::String, env : Hash(::String, PyValue), unknown : Set(::String)) : PyValue | Symbol
      expr = expr.strip
      if m = expr.match(/\A(.+?)\s+if\s+(.+?)\s+else\s+(.+)\z/)
        test = eval_python_condition(m[2], env, unknown)
        return :unknown if test.nil?
        return eval_python_expression(test ? m[1] : m[3], env, unknown)
      end
      if m = expr.match(/\A(.+?)\s+or\s+(.+)\z/)
        left = eval_python_expression(m[1], env, unknown)
        return :unknown if left.is_a?(Symbol)
        return left unless left.nil? || left == false || left == ""
        return eval_python_expression(m[2], env, unknown)
      end
      if expr.matches?(/\A[A-Za-z_]\w*\z/) && !expr.in?("True", "False", "None")
        return :unknown if unknown.includes?(expr) || !env.has_key?(expr)
        return env[expr]
      end
      python_literal(expr)
    end

    private def eval_python_condition(test : ::String, env : Hash(::String, PyValue), unknown : Set(::String)) : Bool?
      if m = test.match(/\A([A-Za-z_]\w*)\s+is\s+(not\s+)?None\z/)
        value = eval_python_expression(m[1], env, unknown)
        return if value.is_a?(Symbol)
        return m[2]? ? !value.nil? : value.nil?
      end
      value = eval_python_expression(test, env, unknown)
      return if value.is_a?(Symbol)
      !(value.nil? || value == false || value == "")
    end

    # Parameter names and default source text of the `def` heading `body`.
    private def python_signature(body : ::String) : Tuple(Array(::String), Hash(::String, ::String))
      params = [] of ::String
      defaults = Hash(::String, ::String).new
      byte_open = body.byte_index('(') || return {params, defaults}
      close = python_close_paren_byte(body.to_slice, byte_open) || return {params, defaults}
      split_python_arguments(body.byte_slice(byte_open + 1, close - byte_open - 1)).each do |param|
        name, eq, default = param.partition('=')
        name = name.partition(':')[0].strip
        next if name.empty? || name.starts_with?('*') || name == "self"
        params << name
        defaults[name] = default.strip unless eq.empty?
      end
      {params, defaults}
    end

    private def matching_brace(text : ::String, open : Int32) : Int32?
      depth = 0
      quote : Char? = nil
      escaped = false
      (open...text.size).each do |i|
        ch = text[i]
        if quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == quote
            quote = nil
          end
        elsif ch == '\'' || ch == '"'
          quote = ch
        elsif ch == '{'
          depth += 1
        elsif ch == '}'
          depth -= 1
          return i if depth == 0
        end
      end
      nil
    end
  end
end
