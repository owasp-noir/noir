# Part of EndpointOptimizer: GraphQL-specific dedup — operation-vs-transport pruning,
# document-argument params, operation tags.
class EndpointOptimizer
  private def duplicate_graphql_operation_tag?(target : Endpoint, tag : Tag) : Bool
    return false unless graphql_operation_tag?(tag)

    if existing_index = target.tags.index do |existing|
         graphql_operation_tag?(existing) &&
         existing.name == tag.name &&
         existing.description == tag.description
       end
      target.tags[existing_index] = tag if tag.tagger == "graphql_sdl_analyzer"
      return true
    end

    false
  end

  private def graphql_operation_tag?(tag : Tag) : Bool
    tag.name == "graphql" &&
      tag.description.matches?(/^(Query|Mutation|Subscription|Schema|Object|Field)\./)
  end

  private def prune_collection_graphql_transport_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    operation_paths = Set(String).new
    endpoints.each do |endpoint|
      next unless graphql_operation_endpoint?(endpoint)
      operation_paths << graphql_transport_path(endpoint.url)
    end
    return endpoints if operation_paths.empty?

    endpoints.reject do |endpoint|
      collection_graphql_transport_noise?(endpoint, operation_paths)
    end
  end

  private def collection_graphql_transport_noise?(endpoint : Endpoint, operation_paths : Set(String)) : Bool
    return false unless collection_endpoint?(endpoint)
    return false unless endpoint.method == "POST"
    return false unless operation_paths.includes?(graphql_transport_path(endpoint.url))
    return false if endpoint.url.includes?("#")

    endpoint.params.all? { |param| collection_noise_header_param?(param) }
  end

  private def graphql_operation_endpoint?(endpoint : Endpoint) : Bool
    endpoint.url.matches?(/#[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*/)
  end

  private def graphql_transport_path(url : String) : String
    url.split('#', 2).first
  end

  private def merge_graphql_params(target : Endpoint, source : Endpoint) : Nil
    target_sdl = graphql_sdl_endpoint?(target)
    source_sdl = graphql_sdl_endpoint?(source)

    source.params.each do |param|
      if graphql_doc_param?(param)
        if existing_index = target.params.index { |target_param| target_param.name == param.name && target_param.param_type == param.param_type }
          target.params[existing_index] = param if source_sdl && !target_sdl
        else
          target.params << param
        end
      else
        existing_param = target.params.find { |target_param| target_param.name == param.name && target_param.param_type == param.param_type }
        target.params << param unless existing_param
      end
    end

    prune_graphql_argument_params(target) if target_sdl || source_sdl

    if source_sdl && !target_sdl
      details = target.details
      details.technology = source.details.technology
      target.details = details
    end
  end

  private def graphql_endpoint?(endpoint : Endpoint) : Bool
    endpoint.url.includes?("#Query.") ||
      endpoint.url.includes?("#Mutation.") ||
      endpoint.url.includes?("#Subscription.")
  end

  private def graphql_sdl_endpoint?(endpoint : Endpoint) : Bool
    tech = endpoint.details.technology
    return true if tech == "graphql_sdl"

    endpoint.tags.any? { |tag| tag.tagger == "graphql_sdl_analyzer" }
  end

  private def graphql_doc_param?(param : Param) : Bool
    param.param_type == "json" &&
      param.name.starts_with?("graphql_") &&
      param.value.matches?(/\A\s*(?:query|mutation|subscription)\b/)
  end

  private def prune_graphql_argument_params(endpoint : Endpoint) : Nil
    return unless endpoint.params.any? { |param| graphql_doc_param?(param) }

    allowed_names = graphql_document_arg_names(endpoint)
    expanded_input_names = graphql_expanded_input_argument_names(endpoint)
    endpoint.params.reject! do |param|
      param.param_type == "json" &&
        !graphql_doc_param?(param) &&
        !graphql_input_field_param?(param) &&
        (!allowed_names.includes?(param.name) || expanded_input_names.includes?(param.name))
    end
  end

  private def graphql_input_field_param?(param : Param) : Bool
    param.tags.any? { |tag| graphql_input_field_tag?(tag) }
  end

  private def graphql_expanded_input_argument_names(endpoint : Endpoint) : Array(String)
    names = [] of String
    endpoint.params.each do |param|
      param.tags.each do |tag|
        next unless graphql_input_field_tag?(tag)
        names << tag.description unless tag.description.empty?
      end
    end
    names.uniq
  end

  private def graphql_input_field_tag?(tag : Tag) : Bool
    tag.name == "graphql-input-field" &&
      {"kotlin_spring_graphql_analyzer", "graphql_sdl_analyzer"}.includes?(tag.tagger)
  end

  private def graphql_document_arg_names(endpoint : Endpoint) : Array(String)
    names = [] of String
    endpoint.params.each do |param|
      next unless graphql_doc_param?(param)
      names.concat(graphql_arg_names_from_document(param.value))
    end
    names.uniq
  end

  private def graphql_arg_names_from_document(document : String) : Array(String)
    match = document.match(/\A\s*(?:query|mutation|subscription)(?:\s+[A-Za-z_][A-Za-z0-9_]*)?\s*\(([^)]*)\)/)
    return [] of String unless match

    names = [] of String
    match[1].scan(/\$([A-Za-z_][A-Za-z0-9_]*)\s*:/) do |arg_match|
      names << arg_match[1]
    end
    names
  end
end
