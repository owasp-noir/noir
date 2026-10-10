require "wait_group"
require "./optimizer"
require "../llm/adapter"
require "../llm/cache"
require "../llm/prompt"
require "../llm/prompt_overrides"

# Enhanced optimizer with LLM-based optimization capabilities
# for refining non-standard or unconventional paths and parameters
class LLMEndpointOptimizer < EndpointOptimizer
  @use_llm : Bool = false
  @adapter : LLM::Adapter? = nil
  @provider : String = ""
  @model : String = ""

  def initialize(@logger : NoirLogger, @options : Hash(String, YAML::Any))
    super(@logger, @options)
    setup_llm_adapter
  end

  # Enhanced optimization with LLM capabilities
  def optimize(endpoints : Array(Endpoint)) : Array(Endpoint)
    # First run standard optimization
    optimized = super(endpoints)

    # Then apply LLM optimization if enabled
    if @use_llm && (adapter = @adapter)
      begin
        optimized = llm_optimize_endpoints(optimized)
      ensure
        # An ACP provider backs the adapter with a spawned agent process;
        # without this it outlives the scan (nothing else holds a reference
        # to close it) and noir exits leaving the agent running.
        adapter.close
        @adapter = nil
        @use_llm = false
      end
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
      candidate_indexes << i if ai_only?(endpoint) && has_non_standard_patterns(endpoint)
    end

    if candidate_indexes.empty?
      @logger.debug_sub "No endpoints found that would benefit from LLM optimization."
      return endpoints
    end

    # One metered request per candidate: say how many before paying.
    if candidate_indexes.size > MAX_OPTIMIZE_REQUESTS
      @logger.info "LLM optimizer: #{candidate_indexes.size} candidate endpoints, optimizing the first #{MAX_OPTIMIZE_REQUESTS}."
      candidate_indexes = candidate_indexes.first(MAX_OPTIMIZE_REQUESTS)
    else
      @logger.info "LLM optimizer: #{candidate_indexes.size} candidate endpoint(s)."
    end

    results = optimize_concurrently(candidate_indexes.map { |idx| endpoints[idx] })

    final_endpoints = endpoints.dup
    # The dedup pass already ran, so a rewrite onto another endpoint's
    # (method, url) — a model answering `/api/items` for every route —
    # would replace distinct routes with duplicates. Keep the original URL.
    # Checked here, in candidate order, so the winner does not depend on
    # which request finished first.
    taken = endpoints.map { |endpoint| {endpoint.method, endpoint.url} }.to_set
    candidate_indexes.each_with_index do |idx, i|
      original = final_endpoints[idx]
      optimized = results[i]
      if optimized.url != original.url && !taken.add?({optimized.method, optimized.url})
        @logger.debug_sub "  - URL rewrite #{original.url} → #{optimized.url} rejected: collides with another endpoint"
        optimized.url = original.url
      end
      final_endpoints[idx] = optimized
    end

    final_endpoints
  end

  # Same bounded pool as the AI analyzer's bundles: a few requests in
  # flight, never one per candidate, and one at a time for an ACP agent,
  # which serializes prompts anyway.
  private def optimize_concurrently(candidates : Array(Endpoint)) : Array(Endpoint)
    results = candidates.dup
    queue = Channel(Int32).new(candidates.size)
    candidates.each_index { |i| queue.send(i) }
    queue.close

    workers = LLM::ACPClient.acp_provider?(@provider) ? 1 : (@options["concurrency"]?.try(&.to_s.to_i?) || 1).clamp(1, MAX_OPTIMIZE_WORKERS)
    WaitGroup.wait do |wg|
      Math.min(workers, candidates.size).times do
        wg.spawn do
          while i = queue.receive?
            results[i] = llm_optimize_single_endpoint(candidates[i])
          end
        end
      end
    end
    results
  end

  # Only routes the AI analyzer alone reported. A static analyzer read the
  # route out of the code; the model only sees the URL, so it cannot know
  # which spelling is real and a rewrite can only make it wrong.
  private def ai_only?(endpoint : Endpoint) : Bool
    details = endpoint.details
    details.technology == "ai" && details.technologies.all?("ai")
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
      response_str = request_optimization(prompt, adapter)
      @logger.debug_sub "LLM optimization response for #{endpoint.method} #{endpoint.url}:"
      @logger.debug_sub response_str

      # Parse response and apply optimizations
      apply_llm_optimizations(endpoint, response_str)
    rescue ex : Exception
      @logger.debug "LLM optimization failed for endpoint #{endpoint.method} #{endpoint.url}: #{ex.message}"
      endpoint
    end
  end

  # One request per non-standard endpoint adds up fast: a repeat scan of
  # the same project used to re-pay for every one of them, because this
  # path never touched the disk cache the AI analyzer has used all along.
  # Same key scheme, so `noir cache clear`/`purge` govern both.
  private def request_optimization(prompt : String, adapter : LLM::Adapter) : String
    key = LLM::Cache.key(@provider, @model, "LLM_OPTIMIZE", LLM_OPTIMIZE_FORMAT, prompt)
    if cached = LLM::Cache.fetch(key)
      return cached
    end

    response = adapter.request(prompt, LLM_OPTIMIZE_FORMAT).to_s
    # An empty or unparsable response means the request failed; caching it
    # would replay the failure on every later scan until the cache was
    # cleared by hand.
    LLM::Cache.store(key, response) if optimization_reply(response)
    response
  end

  # Either field makes it an answer: a model that ignores the schema and
  # sends only `optimized_params` still has a usable correction.
  private def optimization_reply(response : String) : Hash(String, JSON::Any)?
    LLM.json_reply(response, "optimized_url") || LLM.json_reply(response, "optimized_params")
  end

  # The part of an endpoint URL a rewrite may not change: the -u target
  # (base path included) when the URL carries it, else an absolute URL's own
  # scheme and host.
  private def rewrite_prefix(url : String) : String
    target = @options["url"]?.to_s.chomp("/")
    return target if !target.empty? && (url == target || url.starts_with?("#{target}/"))
    url[URL_ORIGIN_RE]? || ""
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
      PROMPT
  end

  # Apply LLM optimization suggestions to an endpoint
  private def apply_llm_optimizations(endpoint : Endpoint, response : String) : Endpoint
    optimization_data = optimization_reply(response)
    return endpoint if optimization_data.nil?

    optimized_endpoint = endpoint
    # With -u the URL is already prefixed. Rewrite only what follows the
    # prefix: a path-only answer used to drop scheme, host and base path,
    # and a full URL answer was rejected outright. The model was shown the
    # full URL, so a path-only answer may repeat the base path.
    prefix = rewrite_prefix(endpoint.url)
    path = endpoint.url[prefix.size..]

    # Apply URL optimizations if suggested
    if optimization_data.has_key?("optimized_url")
      new_url = optimization_data["optimized_url"].as_s
      base_path = prefix.sub(URL_ORIGIN_RE, "")
      if !prefix.empty? && new_url.starts_with?("#{prefix}/")
        new_url = new_url[prefix.size..]
      elsif !base_path.empty? && new_url.starts_with?("#{base_path}/")
        new_url = new_url[base_path.size..]
      end
      # Only accept a rewrite that is a real path. Without this guard a
      # model that returns prose, a code fragment, or a "/GET /x"-style
      # string (anything that merely starts with "/") would clobber a
      # correct URL — corrupting the endpoint (a false positive) and
      # losing the original (a false negative) in one step.
      if new_url.starts_with?("/") && plausible_rewrite_url?(new_url) && new_url != path && derivable_rewrite?(path, new_url)
        @logger.debug_sub "  - URL optimized: #{endpoint.url} → #{prefix}#{new_url}"
        optimized_endpoint.url = "#{prefix}#{new_url}"
        path = new_url
      end
    end

    # Apply parameter optimizations if suggested. Only the type of a known
    # param may change, plus a name for a wildcard the URL now names:
    # replacing the list wholesale renamed `userID` to `user_id` while the
    # URL kept `:userID`, and dropped whatever the model left out.
    if optimization_data.has_key?("optimized_params")
      url_names = route_shape(path)[1]
      optimized_params = endpoint.params.dup
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
        # A path param is exactly a name the URL carries.
        next if (param_type == "path") != url_names.includes?(name)

        if idx = optimized_params.index { |param| param.name == name }
          param = optimized_params[idx]
          param.param_type = param_type
          optimized_params[idx] = param
        else
          value = param_obj.has_key?("value") ? param_obj["value"].as_s : ""
          optimized_params << Param.new(name, value, param_type)
        end
      end

      if optimized_params != endpoint.params
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
      # `ai_key` defaults to "" in the config, and an empty string is not a
      # missing key: passed through verbatim it used to suppress the
      # documented NOIR_AI_KEY fallback, so every optimization request
      # 401'd for users who authenticate through the env var.
      api_key = @options["ai_key"]?.try(&.to_s.presence)
    end

    if any_to_bool(@options["ai_no_optimize"]?)
      @use_llm = false
      @logger.debug "LLM optimization disabled by --ai-no-optimize"
    elsif !provider.empty? && (!model.empty? || LLM::ACPClient.acp_provider?(provider))
      @use_llm = true
      @provider = provider
      @model = model
      # The same `num_ctx` the analyzer's Ollama client sent: a different
      # one makes Ollama reload the model between the two phases.
      context_tokens = if LLM::AdapterFactory.ollama_native?(provider)
                         LLM.effective_max_tokens(provider, model, @options["ai_max_token"]?.try(&.as_i?) || 0)
                       end
      @adapter = LLM::AdapterFactory.for(provider, model, api_key, context_tokens: context_tokens)
      @logger.debug_sub "LLM optimization enabled with #{Noir::Redact.url(provider)}: #{model}"
    else
      @use_llm = false
      @logger.debug "LLM optimization disabled - missing required configuration"
    end
  end

  # Matches Analyzer::AI::Unified::MAX_BUNDLE_WORKERS.
  MAX_OPTIMIZE_WORKERS  =   4
  MAX_OPTIMIZE_REQUESTS = 100

  VALID_PARAM_TYPES        = %w[query json form header cookie path]
  MAX_REWRITE_URL_LENGTH   = 2048
  MAX_OPTIMIZED_PARAM_NAME =  128
  URL_ORIGIN_RE            = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\/?#]*/

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

  # One path-param token in any spelling the analyzers emit: `{name}`,
  # `{name:regex}`, `{...rest}`, `:name`, `<name>`, `<conv:name>`, or an
  # unnamed `*` wildcard. A `:` right after a word char is literal text
  # (`/v1/items:batchGet`), not a param.
  ROUTE_PARAM_RE = /\{(?:\.\.\.)?([^{}:]+)(?::[^{}]*)?\}|<(?:[^<>:]+:)?([^<>]+)>|(?<!\w):([A-Za-z_]\w*)|\*+/

  # A route's literal text with each param replaced by a marker, and the
  # param names in order (nil for a wildcard).
  private def route_shape(path : String) : {String, Array(String?)}
    names = [] of String?
    skeleton = path.gsub(ROUTE_PARAM_RE) do |_, match|
      names << (match[1]? || match[2]? || match[3]?)
      "\0"
    end
    {skeleton, names}
  end

  # A rewrite may respell the route's params but not change the route: the
  # literal text must match byte for byte and every named param keeps its
  # name. Only an unnamed wildcard may gain one. The model sees a URL, not
  # the code, so anything more is a guess at a route the app may not serve.
  private def derivable_rewrite?(original : String, rewrite : String) : Bool
    skeleton, names = route_shape(original)
    new_skeleton, new_names = route_shape(rewrite)
    skeleton == new_skeleton && names.size == new_names.size &&
      names.zip(new_names).all? { |old, new| old.nil? || old == new }
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
