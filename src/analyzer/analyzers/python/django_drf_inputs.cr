require "../../../miniparsers/python_declarations"

module Analyzer::Python
  class Django < PythonEngine
    alias PyScope = Noir::PythonDeclarations::Scope
    alias DrfBinding = Tuple(String, String)

    @drf_modules = {} of String => PyScope
    @drf_settings = {} of String => Hash(String, String)
    @serializer_inputs = {} of DrfBinding => Array(String)
    @settings_file : String?
    @drf_urlconf : String?

    private def declarations(file : String) : PyScope
      @drf_modules[file] ||= Noir::PythonDeclarations.parse(view_file_index(file).content)
    end

    private def scope(klass : DrfClass) : PyScope
      declarations(klass.filepath).classes[klass.name]? || PyScope.new
    end

    private def class_attribute(chain : Array(DrfClass), key : String) : DrfBinding?
      chain.each do |klass|
        parsed = declarations(klass.filepath).classes[klass.name]?
        value = if parsed
                  parsed.attributes[key]?
                else
                  klass.codeblock.match(/^\s+#{Regex.escape(key)}\s*=\s*([\w.]+)\s*$/m).try(&.[1])
                end
        return {klass.filepath, value} if value
      end
      nil
    end

    private def class_method(chain : Array(DrfClass), name : String) : DrfBinding?
      chain.each do |klass|
        if body = scope(klass).methods[name]?
          return {klass.filepath, body}
        end
      end
      nil
    end

    private def literal_items(expression : String) : Array(String)
      return [] of String unless expression[0]?.in?('[', '(', '{')
      split_python_arguments(expression[1...-1].lines.map { |line| strip_python_comment(line) }.join('\n')).map(&.strip).reject(&.empty?)
    end

    private def call_options(call : String) : Hash(String, String)
      options = {} of String => String
      _, separator, args = call.partition('(')
      return options if separator.empty?
      literal_items("(#{args}").each do |arg|
        name, equals, value = arg.partition('=')
        options[name.strip] = value.strip unless equals.empty?
      end
      options
    end

    private def quoted_name(expression : String) : String?
      expression.match(/\A(['"])([\w.:-]+)\1\z/).try(&.[2])
    end

    private def literal_dict(expression : String) : Hash(String, String)
      values = {} of String => String
      return values unless expression.starts_with?('{')
      literal_items(expression).each do |pair|
        key, _, value = pair.partition(':')
        quoted_name(key.strip).try { |name| values[name] = value.strip }
      end
      values
    end

    @project_drf_settings = {} of String => String?

    private def project_drf_settings(file : String) : String?
      root = python_project_root(file)
      @project_drf_settings.fetch(root) do
        candidates = python_source_files.select do |path|
          django_settings_path?(path) && python_project_root(path) == root &&
            declarations(path).attributes.has_key?("REST_FRAMEWORK")
        end
        @project_drf_settings[root] = candidates.size == 1 ? candidates.first : nil
      end
    end

    private def drf_setting(key : String) : DrfBinding?
      file = @settings_file
      unless file
        urlconf = @drf_urlconf || return
        file = project_drf_settings(urlconf) || return
      end
      values = @drf_settings[file] ||= literal_dict(declarations(file).attributes["REST_FRAMEWORK"]?.to_s)
      values[key]?.try { |value| {file, value} }
    end

    # Settings use import strings, whereas view attributes use Python names.
    private def configured_class(file : String, expression : String) : Array(DrfClass)
      target = if dotted = quoted_name(expression)
                 mod, _, name = dotted.rpartition('.')
                 unless mod.empty?
                   path = get_files_by_relative_path("#{mod.gsub('.', '/')}.py", @django_base_path).first? ||
                          get_files_by_relative_path("#{mod.gsub('.', '/')}/__init__.py", @django_base_path).first?
                   path.try { |p| python_definition_site(p, name) }
                 end
               else
                 resolve_python_class(file, expression)
               end
      target ? drf_class_chain(*target) : [] of DrfClass
    end

    private def configured_bases(expression : String, chain : Array(DrfClass)) : Array(String)
      names = chain.flat_map { |klass| python_class_bases(klass.header) }
      names << (quoted_name(expression) || expression)
      names.map(&.rpartition('.')[2])
    end

    private def backend_query_param(backend : Array(DrfClass), attr : String, setting : String, fallback : String) : Param?
      bound = class_attribute(backend, attr)
      configured = drf_setting(setting)
      value = bound.try(&.[1])
      value = configured.try(&.[1]) if !value || value.ends_with?(".#{setting}")
      return if value == "None"
      name = value.try { |v| quoted_name(v) }
      param = Param.new(name || configured.try { |pair| quoted_name(pair[1]) } || fallback, "", "query")
      if value && !name
        param.tags << Tag.new("conditional", "The backend selects the query parameter name at runtime.", TAGGER)
      end
      param
    end

    private def filter_field_names(value : String) : Array(String)
      return literal_items(value).compact_map { |item| quoted_name(item) } unless value.starts_with?('{')
      literal_dict(value).flat_map do |name, lookups|
        literal_items(lookups).compact_map do |item|
          quoted_name(item).try { |lookup| lookup == "exact" ? name : "#{name}__#{lookup}" }
        end
      end
    end

    private def filterset_names(chain : Array(DrfClass)) : Array(String)
      if binding = class_attribute(chain, "filterset_class")
        filters = configured_class(*binding)
        unless filters.empty?
          names = [] of String
          filters.each do |klass|
            scope(klass).attributes.each do |name, value|
              names << name if value.matches?(/\A[\w.]*Filter\s*\(/)
            end
          end
          if fields = drf_meta_attribute({filters.first.filepath, filters.first.name}, "fields")
            names.concat filter_field_names(fields[1])
          end
          return names.uniq
        end
      end
      filter_field_names(class_attribute(chain, "filterset_fields").try(&.[1]).to_s)
    end

    private def drf_backend_params(chain : Array(DrfClass), action : String) : Array(Param)
      params = [] of Param
      binding = action_kwarg(chain, action, "filter_backends") || class_attribute(chain, "filter_backends") || drf_setting("DEFAULT_FILTER_BACKENDS")
      return params unless binding
      if override = class_method(chain, "filter_queryset")
        return params unless override[1].matches?(/\b(?:super\(\)\.filter_queryset|self\.filter_backends)\b/)
      end
      literal_items(binding[1]).each do |entry|
        backend = configured_class(binding[0], entry)
        bases = configured_bases(entry, backend)
        if bases.includes?("DjangoFilterBackend")
          filterset_names(chain).each { |name| params << Param.new(name, "", "query") }
        elsif bases.includes?("SearchFilter")
          search = class_attribute(chain, "search_fields")
          empty = !search || search[1].in?("None", "[]", "()")
          next if empty && !class_method(backend, "get_search_fields")
          backend_query_param(backend, "search_param", "SEARCH_PARAM", "search").try { |param| params << param }
        elsif bases.includes?("OrderingFilter")
          backend_query_param(backend, "ordering_param", "ORDERING_PARAM", "ordering").try { |param| params << param }
        end
      end
      params
    end

    # GenericAPIView.get_object filters the queryset before looking up a
    # detail object. Respect overrides which perform the lookup themselves.
    private def filters_object?(chain : Array(DrfClass)) : Bool
      body = class_method(chain, "get_object")
      !body || body[1].matches?(/\b(?:self\.filter_queryset|super\(\)\.get_object)\s*\(/)
    end

    private def generic_query_params(chain : Array(DrfClass), header : String, verb : String) : Array(Param)
      params = [] of Param
      list = verb == "GET" && header.matches?(/\bList(?:Create)?APIView\b/)
      action = list ? "list" : {"GET" => "retrieve", "POST" => "create", "PUT" => "update", "PATCH" => "partial_update", "DELETE" => "destroy"}.fetch(verb, verb.downcase)
      detail = verb != "POST" && header.matches?(/\b(?:Retrieve|Update|Destroy)\w*APIView\b/)

      # Generic handlers delegate to the action on self. An override that
      # bypasses the mixin only receives the query inputs it actually reads.
      handlers = [] of String
      stock = list || detail
      [verb.downcase, action].uniq.each do |name|
        next unless binding = class_method(chain, name)
        body = binding[1]
        handlers << body
        next if body.matches?(/\bsuper\(\)\.#{name}\s*\(/)
        next if name == verb.downcase && body.matches?(/\bself\.#{action}\s*\(/)
        stock = false
        break
      end
      code = handlers.join('\n')
      if (stock && list) || code.matches?(PAGINATE_CALL_RE)
        params.concat pagination_params(chain, action)
      end
      lookup = filters_object?(chain)
      if (stock && (list || lookup)) || code.matches?(/\bself\.filter_queryset\s*\(/) || (lookup && code.matches?(/\bself\.get_object\s*\(/))
        params.concat drf_backend_params(chain, action)
      end
      params
    end

    # Resolve Meta where Python inherited it. A new Meta without a Meta
    # base replaces its parent's options entirely.
    private def drf_meta_attribute(target : DrfBinding, key : String, depth = 0) : DrfBinding?
      return if depth > 8
      drf_class_chain(*target).each do |klass|
        meta = scope(klass).classes["Meta"]? || next
        if value = meta.attributes[key]?
          return {klass.filepath, value}
        end
        python_class_bases(meta.bases).each do |base|
          owner = base.rchop?(".Meta") || next
          parent = resolve_python_class(klass.filepath, owner) || next
          if result = drf_meta_attribute(parent, key, depth + 1)
            return result
          end
        end
        break
      end
      nil
    end

    # Expand explicit or starred references to another serializer's Meta
    # list. Keep the literal portion even when an expression is unresolved.
    private def serializer_meta_names(target : DrfBinding, key : String, depth = 0) : Array(String)
      names = [] of String
      return names if depth > 8
      file, value = drf_meta_attribute(target, key) || return names
      terms = Noir::TopLevelSplit.split(value, '+', Noir::TopLevelSplit::Rules::PYTHON).flat_map do |part|
        part = part.strip
        part[0]?.in?('[', '(') ? literal_items(part) : [part]
      end
      terms.each do |item|
        if name = quoted_name(item)
          names << name
        elsif ref = item.match(/\A\*?([\w.]+)\.Meta\.(\w+)\z/)
          parent = resolve_python_class(file, ref[1]) || next
          names.concat serializer_meta_names(parent, ref[2], depth + 1)
        elsif item == "fields" && key != "fields"
          names.concat serializer_meta_names(target, "fields", depth + 1)
        end
      end
      names
    end

    private def model_fields(target : DrfBinding) : Hash(String, Bool)
      fields = {} of String => Bool
      binding = drf_meta_attribute(target, "model") || return fields
      model = resolve_python_class(*binding) || return fields
      drf_class_chain(*model).reverse_each do |klass|
        scope(klass).methods.each_key { |name| fields[name] = false }
        scope(klass).attributes.each do |name, value|
          ctor = value.match(/\A([\w.]+)\s*\(/).try(&.[1].rpartition('.')[2]) || next
          next unless ctor.ends_with?("Field") || ctor.in?("ForeignKey", "OneToOneField")
          options = call_options(value)
          fields[name] = !ctor.ends_with?("AutoField") && options["editable"]? != "False" &&
                         options["auto_now"]? != "True" && options["auto_now_add"]? != "True"
        end
      end
      fields
    end

    private def serializer_inputs(target : DrfBinding, ancestors = [] of DrfBinding) : Array(String)
      chain = drf_class_chain(*target)
      # If the syntax tree could not recover the class, preserve the older
      # declaration scan on the same source.
      return declared_input_fields(target) unless declarations(target[0]).classes.has_key?(target[1])
      names = serializer_meta_names(target, "fields")
      fields = model_fields(target)
      all = names.includes?("__all__")
      names = fields.select { |_, writable| writable }.keys if all
      selection = drf_meta_attribute(target, "fields").try(&.[1])
      # Only a closed literal selection proves an inherited declaration absent.
      closed = !all && selection && selection[0]?.in?('[', '(') && literal_items(selection).all? { |item| quoted_name(item) }
      selected = names.dup
      names.reject! { |name| fields[name]? == false }
      names -= serializer_meta_names(target, "read_only_fields")
      names.reject! { |name| name.in?("id", "pk") && fields[name]? != true }
      names.delete("url") if chain.any?(&.header.includes?("HyperlinkedModelSerializer"))
      if extra = drf_meta_attribute(target, "extra_kwargs")
        literal_dict(extra[1]).each do |name, options|
          names.delete(name) if literal_dict(options)["read_only"]? == "True"
        end
      end
      seen = Set(String).new
      chain.each do |klass|
        scope(klass).attributes.each do |name, value|
          ctor = value.match(/\A([\w.]+(?:Field|Serializer))\s*\(/).try(&.[1]) || next
          next unless seen.add?(name)
          next if closed && !selected.includes?(name)
          names.delete(name)
          next if output_only_field?(ctor, klass.filepath) || call_options(value)["read_only"]? == "True"
          names << name
          next unless ctor.ends_with?("Serializer") && ancestors.size < 6
          nested = resolve_python_class(klass.filepath, ctor) || next
          next if nested == target || ancestors.includes?(nested)
          serializer_inputs(nested, ancestors + [target]).each { |child| names << "#{name}.#{child}" }
        end
      end
      if initializer = class_method(chain, "__init__")
        lines = initializer[1].lines[1..]
        indent = lines.reject(&.blank?).min_of? { |line| line.size - line.lstrip.size }
        lines.each do |line|
          next unless line.size - line.lstrip.size == indent
          if update = line.strip.match(/\Aself\.fields\[['"](\w+)['"]\]\.read_only\s*=\s*True\s*(?:#.*)?\z/)
            names.reject! { |name| name == update[1] || name.starts_with?("#{update[1]}.") }
          end
        end
      end
      names.uniq
    end

    # A versioned serializer factory sometimes takes the name of a serializer
    # chosen by a view helper. Its input class is evidence for possible fields,
    # while the factory's actual result remains request-dependent.
    private def serializer_choices(chain : Array(DrfClass), method : String, action : String?, verb : String?, attribute : DrfBinding?,
                                   depth = 0) : Tuple(Array(DrfBinding), Bool)
      choices = [] of DrfBinding
      return {choices, true} if depth > 4
      site = class_method(chain, method)
      return {attribute ? [attribute] : choices, false} unless site
      file, body = site
      guard = ->(expr : String) { serializer_guard(expr, chain, action, verb) }
      expressions = Noir::PythonDeclarations.reachable_values(body, guard)
      uncertain = expressions.size != 1
      expressions.each do |expr|
        if expr == "super().get_serializer_class()"
          index = chain.index { |klass| scope(klass).methods.has_key?(method) } || next
          inherited, dynamic = serializer_choices(chain[index + 1..], method, action, verb, attribute, depth + 1)
          choices.concat inherited
          uncertain ||= dynamic
          next
        end
        candidates = [expr]
        if wrapped = expr.match(/\A[\w.]+\(\s*(\w+)\.__name__\s*\)\z/)
          candidates = Noir::PythonDeclarations.reachable_values(body, guard, wrapped[1])
          uncertain = true
        elsif expr.matches?(/\A[a-z_]\w*\z/)
          assignments = Noir::PythonDeclarations.reachable_values(body, guard, expr)
          unless assignments.empty?
            candidates = assignments
            uncertain ||= assignments.size > 1
          end
        end
        candidates.each do |candidate|
          if helper = candidate.match(/\Aself\.(\w+)\(\)\z/)
            next unless class_method(chain, helper[1])
            nested, dynamic = serializer_choices(chain, helper[1], action, verb, attribute, depth + 1)
            choices.concat nested
            uncertain ||= dynamic
          elsif attr = candidate.lchop?("self.")
            binding = attr == "serializer_class" ? attribute : class_attribute(chain, attr)
            binding.try { |value| choices << value }
          elsif candidate.matches?(/\A[\w.]+\z/)
            choices << {file, candidate}
          end
        end
      end
      # When dispatch is dynamic, retain the view's known serializer as a candidate.
      if choices.empty? && attribute
        choices << attribute
        uncertain = true
      end
      {choices.uniq, uncertain}
    end

    private def serializer_guard(expr : String, chain : Array(DrfClass), action : String?, verb : String?) : Bool?
      if test = expr.match(/\Aself\.action\s*(==|!=)\s*(['"])([\w-]+)\2\z/)
        return (action == test[3]) != (test[1] == "!=") if action
      elsif test = expr.match(/\Aself\.action\s+in\s*(.+)\z/)
        items = literal_items(test[1])
        return items.any? { |item| quoted_name(item) == action } if action && !items.empty? && items.all? { |item| quoted_name(item) }
      elsif test = expr.match(/\Aself\.request\.method\s+(not\s+)?in\s+SAFE_METHODS(\s+or\s+.+)?\z/)
        if verb
          matches = verb.in?("GET", "HEAD", "OPTIONS") != !test[1]?.nil?
          return matches if matches || !test[2]?
        end
      elsif test = expr.match(/\Ahasattr\(self,\s*['"](\w+)['"]\)\z/)
        return true if class_method(chain, test[1])
      end
      nil
    end
  end
end
