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

    # Filter endpoints that might benefit from LLM optimization, recording their
    # positions. Writing each optimized result back by index avoids the previous
    # identity-normalized find(), which collapsed distinct param names
    # (/api/{userID} and /api/{orderID} both -> /api/{param}) and clobbered
    # sibling endpoints with the first match.
    candidate_indexes = [] of Int32
    endpoints.each_with_index do |endpoint, i|
      candidate_indexes << i if has_non_standard_patterns(endpoint)
    end

    if candidate_indexes.empty?
      @logger.debug_sub "No endpoints found that would benefit from LLM optimization."
      return endpoints
    end

    @logger.debug_sub "Found #{candidate_indexes.size} endpoints that may benefit from LLM optimization."

    final_endpoints = endpoints.dup
    candidate_indexes.each do |idx|
      final_endpoints[idx] = llm_optimize_single_endpoint(final_endpoints[idx])
    end

    final_endpoints
  end

  # Check if an endpoint has non-standard patterns that could benefit from LLM optimization
  private def has_non_standard_patterns(endpoint : Endpoint) : Bool
    url = endpoint.url

    # Look for unusual parameter patterns, complex paths, or non-standard naming
    return true if url.includes?("*")                         # Wildcard patterns
    return true if url.includes?("...")                       # Spread/rest patterns
    return true if url.matches?(/\{[^}]*\|[^}]*\}/)           # Union types in parameters
    return true if url.matches?(/[A-Z]{2,}/)                  # Unusual uppercase segments
    return true if url.matches?(/\d{3,}/)                     # Long numeric segments
    return true if url.includes?("__") || url.includes?("--") # Double separators

    # Check for complex parameter patterns
    return true if endpoint.params.any? do |p|
                     p.name.includes?("_id_") || p.name.matches?(/[A-Z]{2,}/)
                   end

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
    rescue ex : Exception
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
      # Only accept a rewrite that is a real path. Without this guard a
      # model that returns prose, a code fragment, or a "/GET /x"-style
      # string (anything that merely starts with "/") would clobber a
      # correct URL — corrupting the endpoint (a false positive) and
      # losing the original (a false negative) in one step.
      if new_url != endpoint.url && !new_url.empty? && new_url.starts_with?("/") && plausible_rewrite_url?(new_url)
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
        # Drop names that carry whitespace/control chars or are absurdly
        # long — the model captured a description, not an identifier.
        # Mirrors the guard Analyzer::AI::Unified applies to its own
        # responses so the correction step can't reintroduce param FPs.
        next unless valid_optimized_param_name?(name)
        # Normalize whatever string the LLM returns to one of the
        # canonical param types so we don't end up with rogue values
        # like "uri" or "Querystring" propagating into the endpoint
        # model. Mirrors the validation Analyzer::AI::Unified does
        # on its own LLM responses.
        param_type = normalize_param_type(param_obj["param_type"].as_s)
        value = param_obj.has_key?("value") ? param_obj["value"].as_s : ""

        optimized_params << Param.new(name, value, param_type)
      end

      unless optimized_params.empty?
        @logger.debug_sub "  - Parameters optimized: #{endpoint.params.size} → #{optimized_params.size}"
        optimized_endpoint.params = optimized_params
      end
    end

    optimized_endpoint
  rescue ex : Exception
    @logger.debug "Failed to parse LLM optimization response: #{ex.message}"
    endpoint
  end

  # Setup LLM adapter based on configuration
  private def setup_llm_adapter
    # Determine provider and model from options
    provider = ""
    model = ""
    api_key = nil

    if @options.has_key?("ai_provider") && !@options["ai_provider"].to_s.empty?
      provider = @options["ai_provider"].to_s
      raw_model = @options["ai_model"]?.try(&.to_s) || ""
      model = if LLM::ACPClient.acp_provider?(provider)
                LLM::ACPClient.default_model(provider, raw_model)
              else
                raw_model
              end
      api_key = @options["ai_key"]?.try(&.to_s)
    end

    if !provider.empty? && (!model.empty? || LLM::ACPClient.acp_provider?(provider))
      @use_llm = true
      @adapter = LLM::AdapterFactory.for(provider, model, api_key)
      @logger.debug_sub "LLM optimization enabled with #{provider}: #{model}"
    else
      @use_llm = false
      @logger.debug "LLM optimization disabled - missing required configuration"
    end
  end

  VALID_PARAM_TYPES        = %w[query json form header cookie path]
  MAX_REWRITE_URL_LENGTH   = 2048
  MAX_OPTIMIZED_PARAM_NAME =  128

  # Coerce an LLM-supplied param_type string to one of the canonical
  # values; anything outside the list falls back to "query".
  private def normalize_param_type(raw : String) : String
    normalized = raw.downcase
    VALID_PARAM_TYPES.includes?(normalized) ? normalized : "query"
  end

  # A rewritten URL must look like a served path: no raw whitespace,
  # control chars, or markdown noise, and within a sane length bound.
  # Shares the shape check with Analyzer::AI::Unified so the correction
  # phase can't reintroduce what the identification phase rejected.
  private def plausible_rewrite_url?(url : String) : Bool
    LLM.clean_token?(url, MAX_REWRITE_URL_LENGTH)
  end

  # A param name is an identifier-ish token, not a sentence.
  private def valid_optimized_param_name?(name : String) : Bool
    LLM.clean_token?(name, MAX_OPTIMIZED_PARAM_NAME)
  end

  # LLM response format for optimization. The canonical prompt text
  # lives in LLM::PromptOverrides.llm_optimize_prompt — the older
  # LLM_OPTIMIZE_PROMPT constant that used to live here was a dead
  # duplicate and has been removed.
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
