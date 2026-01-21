require "./optimizer"
require "../llm/adapter"
require "../llm/prompt"
require "../llm/prompt_overrides"

# Enhanced optimizer with LLM-based optimization capabilities
# for refining non-standard or unconventional paths and parameters
class LLMEndpointOptimizer < EndpointOptimizer
  @use_llm : Bool = false
  @adapter : LLM::Adapter? = nil

  def initialize(@logger : NoirLogger, @options : Hash(String, YAML::Any))
    super(@logger, @options)
    setup_llm_adapter
  end

  # Enhanced optimization with LLM capabilities
  def optimize(endpoints : Array(Endpoint)) : Array(Endpoint)
    # First run standard optimization
    optimized = super(endpoints)

    # Then apply LLM optimization if enabled
    if @use_llm && @adapter
      optimized = llm_optimize_endpoints(optimized)
    end

    optimized
  end

  # Use LLM to optimize and refine non-standard paths and parameters
  private def llm_optimize_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    return endpoints if endpoints.empty? || !@use_llm || !@adapter

    @logger.info "Applying LLM-based optimization for non-standard paths and parameters."

    # Filter endpoints that might benefit from LLM optimization
    candidates = find_optimization_candidates(endpoints)

    if candidates.empty?
      @logger.debug_sub "No endpoints found that would benefit from LLM optimization."
      return endpoints
    end

    @logger.debug_sub "Found #{candidates.size} endpoints that may benefit from LLM optimization."

    optimized_endpoints = [] of Endpoint

    candidates.each do |endpoint|
      optimized_endpoint = llm_optimize_single_endpoint(endpoint)
      optimized_endpoints << optimized_endpoint
    end

    # Replace optimized endpoints in the original array
    final_endpoints = endpoints.map do |endpoint|
      optimized = optimized_endpoints.find { |opt| matches_endpoint_identity(endpoint, opt) }
      optimized || endpoint
    end

    final_endpoints
  end

  # Find endpoints that would benefit from LLM optimization
  private def find_optimization_candidates(endpoints : Array(Endpoint)) : Array(Endpoint)
    candidates = [] of Endpoint

    endpoints.each do |endpoint|
      # Check for non-standard URL patterns that might need refinement
      if has_non_standard_patterns(endpoint)
        candidates << endpoint
      end
    end

    candidates
  end

  # Check if an endpoint has non-standard patterns that could benefit from LLM optimization
  private def has_non_standard_patterns(endpoint : Endpoint) : Bool
    url = endpoint.url

    # Look for unusual parameter patterns, complex paths, or non-standard naming
    return true if url.includes?("*")                         # Wildcard patterns
    return true if url.includes?("...")                       # Spread/rest patterns
    return true if url.scan(/\{[^}]*\|[^}]*\}/).size > 0      # Union types in parameters
    return true if url.scan(/[A-Z]{2,}/).size > 0             # Unusual uppercase segments
    return true if url.scan(/\d{3,}/).size > 0                # Long numeric segments
    return true if url.includes?("__") || url.includes?("--") # Double separators

    # Check for complex parameter patterns
    params_text = endpoint.params.map(&.name).join(" ")
    return true if params_text.includes?("_id_")          # Complex ID patterns
    return true if params_text.scan(/[A-Z]{2,}/).size > 0 # Unusual naming patterns

    false
  end

  # Use LLM to optimize a single endpoint
  private def llm_optimize_single_endpoint(endpoint : Endpoint) : Endpoint
    adapter = @adapter
    return endpoint unless adapter

    # Create optimization prompt
    prompt = create_optimization_prompt(endpoint)

    begin
      response = adapter.request(prompt, LLM_OPTIMIZE_FORMAT)
      response_str = response.to_s
      @logger.debug_sub "LLM optimization response for #{endpoint.method} #{endpoint.url}:"
      @logger.debug_sub response_str

      # Parse response and apply optimizations
      apply_llm_optimizations(endpoint, response_str)
    rescue Exception
      @logger.debug "LLM optimization failed for endpoint #{endpoint.method} #{endpoint.url}: #{ex.message}"
      endpoint
    end
  end

  # Create LLM prompt for endpoint optimization
  private def create_optimization_prompt(endpoint : Endpoint) : String
    params_info = endpoint.params.map do |param|
      "- #{param.name} (#{param.param_type}): #{param.value}"
    end.join("\n")

    <<-PROMPT
      #{LLM::PromptOverrides.llm_optimize_prompt}

      Endpoint to optimize:
      - Method: #{endpoint.method}
      - URL: #{endpoint.url}
      - Parameters:
      #{params_info}

      Please provide optimized versions with improved naming, structure, and parameter handling.
      PROMPT
  end

  # Apply LLM optimization suggestions to an endpoint
  private def apply_llm_optimizations(endpoint : Endpoint, response : String) : Endpoint
    optimization_data = JSON.parse(response).as_h

    optimized_endpoint = endpoint

    # Apply URL optimizations if suggested
    if optimization_data.has_key?("optimized_url")
      new_url = optimization_data["optimized_url"].as_s
      if new_url != endpoint.url && new_url.size > 0 && new_url.starts_with?("/")
        @logger.debug_sub "  - URL optimized: #{endpoint.url} → #{new_url}"
        optimized_endpoint.url = new_url
      end
    end

    # Apply parameter optimizations if suggested
    if optimization_data.has_key?("optimized_params")
      optimized_params = [] of Param
      optimization_data["optimized_params"].as_a.each do |param_data|
        param_obj = param_data.as_h
        name = param_obj["name"].as_s
        param_type = param_obj["param_type"].as_s
        value = param_obj.has_key?("value") ? param_obj["value"].as_s : ""

        optimized_params << Param.new(name, value, param_type)
      end

      if optimized_params.size > 0
        @logger.debug_sub "  - Parameters optimized: #{endpoint.params.size} → #{optimized_params.size}"
        optimized_endpoint.params = optimized_params
      end
    end

    optimized_endpoint
  rescue Exception
    @logger.debug "Failed to parse LLM optimization response: #{ex.message}"
    endpoint
  end

  # Check if two endpoints represent the same logical endpoint for replacement
  private def matches_endpoint_identity(original : Endpoint, optimized : Endpoint) : Bool
    # Match by method and similar URL structure (before optimization)
    return false unless original.method == optimized.method

    # For identity matching, use a flexible comparison that accounts for
    # parameter names and basic URL structure
    original_base = original.url.gsub(/\{[^}]+\}/, "{param}").gsub(/:[\w]+/, ":param").gsub(/<[^>]+>/, "<param>")
    optimized_base = optimized.url.gsub(/\{[^}]+\}/, "{param}").gsub(/:[\w]+/, ":param").gsub(/<[^>]+>/, "<param>")

    original_base == optimized_base
  end

  # Setup LLM adapter based on configuration
  private def setup_llm_adapter
    # Determine provider and model from options
    provider = ""
    model = ""
    api_key = nil

    if @options.has_key?("ai_provider") && !@options["ai_provider"].to_s.empty?
      provider = @options["ai_provider"].to_s
      model = @options["ai_model"]?.try(&.to_s) || ""
      api_key = @options["ai_key"]?.try(&.to_s)
    elsif @options.has_key?("ollama") && !@options["ollama"].to_s.empty?
      provider = @options["ollama"].to_s
      model = @options["ollama_model"]?.try(&.to_s) || ""
    end

    if !provider.empty? && !model.empty?
      @use_llm = true
      @adapter = LLM::AdapterFactory.for(provider, model, api_key)
      @logger.debug_sub "LLM optimization enabled with #{provider}: #{model}"
    else
      @use_llm = false
      @logger.debug "LLM optimization disabled - missing required configuration"
    end
  end

  # LLM prompt for optimization
  LLM_OPTIMIZE_PROMPT = <<-PROMPT
    Analyze the provided endpoint and optimize it for better structure, naming conventions, and parameter handling.

    Focus on:
    - Normalizing unusual URL patterns
    - Improving parameter naming conventions
    - Standardizing path structures
    - Removing redundant or confusing elements

    Guidelines:
    - Keep the core functionality and meaning intact
    - Use RESTful conventions where appropriate
    - Ensure parameter types are accurate
    - Maintain endpoint uniqueness
    - Do not include explanations or comments
    - Output only the JSON result according to the schema
    PROMPT

  # LLM response format for optimization
  LLM_OPTIMIZE_FORMAT = <<-JSON
    {
      "type": "json_schema",
      "json_schema": {
        "name": "optimize_endpoint",
        "schema": {
          "type": "object",
          "properties": {
            "optimized_url": {
              "type": "string"
            },
            "optimized_params": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "param_type": {
                    "type": "string"
                  },
                  "value": {
                    "type": "string"
                  }
                },
                "required": ["name", "param_type", "value"],
                "additionalProperties": false
              }
            }
          },
          "required": ["optimized_url", "optimized_params"],
          "additionalProperties": false
        },
        "strict": true
      }
    }
    JSON
end
