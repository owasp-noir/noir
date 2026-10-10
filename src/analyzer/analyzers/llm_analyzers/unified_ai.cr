require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/adapter"
require "../../../llm/prompt"
require "../../../llm/prompt_overrides"
require "../../../llm/cache"
require "../../../models/skipped_files"
require "../../../utils/text_file"

module Analyzer::AI
  # Unified AI analyzer that uses a provider-agnostic LLM adapter.
  # Supports both OpenAI-compatible APIs and Ollama.
  class Unified < Analyzer
    analyzer_for "ai"

    alias AgentAction = NamedTuple(action: String, args: JSON::Any)

    AGENT_TOOL_MAX_LINES               = 300
    AGENT_TOOL_MAX_MATCHES             = 200
    AGENT_MAX_READ_BYTES               = 10 * 1024
    AGENT_MAX_DEPTH                    = 6
    AGENT_TOOL_RESULT_MAX_CHARS        = 16 * 1024
    AGENT_TOOL_CACHE_MAX_ENTRIES       = 96
    AGENT_CONTEXT_MAX_DYNAMIC_MESSAGES = 16
    AGENT_CONTEXT_MAX_CHARS            = 100 * 1024
    AGENT_GREP_SNIPPET_MAX_CHARS       = 220
    AGENT_DEFAULT_FILE_PATTERN         = "*.{go,py,js,ts,java,rb,php,cs,cr,kt,rs,swift,scala,graphql}"
    VALID_METHODS                      = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "QUERY"]
    VALID_PARAM_TYPES                  = ["query", "json", "form", "header", "cookie", "path"]
    MAX_ENDPOINT_URL_LENGTH            = 2048
    MAX_PARAM_NAME_LENGTH              =  128
    # Expanded code paths of the static endpoints, set by
    # `analysis_endpoints` under `--ai-scope unmatched`.
    COVERED_FILES_OPTION = "ai_covered_files"
    URL_AUTHORITY_RE     = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\/]*/
    # `:id`, `{id}`, `<int:id>`, `[id]`, `*`: not literal text to look for.
    PLACEHOLDER_SEGMENT_RE = /[:{}<>\[\]*]/
    # Ceiling on simultaneous bundle requests, independent of a high
    # `--concurrency`: past a handful of in-flight calls a metered provider
    # answers with 429s rather than faster.
    MAX_BUNDLE_WORKERS = 4
    # Provider aliases whose default URL is on this host (see LLM::General).
    LOCAL_PROVIDERS = {"ollama", "lmstudio", "vllm"}
    # Bare URL tokens the LLM emits when it has nothing real to report
    # (schema echoes, "no endpoint" stand-ins). Compared case-folded
    # against the whole path with a single leading slash stripped, so a
    # legitimate nested route like `/example/users` is never rejected —
    # only a URL that IS one of these placeholders is dropped.
    PLACEHOLDER_URLS = Set{
      "url", "uri", "endpoint", "n/a", "na", "none", "null", "nil",
      "undefined", "your_endpoint", "your-endpoint", "path/to/endpoint",
      "...", "<url>", "<endpoint>", "<path>",
    }
    # Every adapter maps a call it could not complete — an HTTP error the
    # retries did not clear, a provider error body, a refused or empty reply,
    # a dead ACP agent, a request skipped after repeated failures — to an
    # empty string, usually after a WARNING naming the cause. The empty string
    # is what reaches here, so this is the reason the *analyzer* can attach to
    # the lost coverage; it must stay true when no warning was printed.
    LLM_NO_RESPONSE_REASON = "the AI provider returned no usable response (an error, a refused or empty reply, or a request skipped after repeated failures)"

    IGNORE_EXTENSIONS = [".css", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico",
                         ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar",
                         ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv",
                         ".log", ".sql", ".bak", ".swp", ".jar"] of String

    # Files that exist to hold credentials. Matched on the basename and
    # withheld from every request — path listing, bundles, per-file prompts
    # and agent tools — unless `--ai-include-sensitive` is given. Source-code
    # extensions are deliberately absent from `secrets.*`: `secrets.go` is as
    # likely a route file as a vault.
    SENSITIVE_FILE = /\A(?:\.env(?:\..*)?|\.envrc|\.npmrc|\.pypirc|\.netrc|_netrc|\.pgpass|\.htpasswd|\.git-credentials|\.dockercfg|id_(?:rsa|dsa|ecdsa|ed25519)(?:\..*)?|credentials(?:\.(?:json|ya?ml|xml|ini|toml|csv|enc|yml\.enc))?|[\w.-]*[-_]credentials\.json|service[-_]?account[\w.-]*\.json|kubeconfig|secrets?\.(?:json|ya?ml|xml|ini|toml|env|enc|txt|properties)|.*\.(?:pem|key|p12|pfx|jks|keystore|kdbx|ppk|asc|gpg|tfvars|tfvars\.json|tfstate|tfstate\.backup))\z/i

    @provider : String
    @model : String
    @api_key : String?
    @max_tokens : Int32
    @expanded_base_paths : Array(String)
    @real_base_paths : Array(String)
    @use_agentic : Bool
    @agent_max_steps : Int32
    @native_tool_calling_allowlist : Array(String)?
    @agent_tool_cache : Hash(String, String)
    @agent_tool_cache_order : Array(String)
    @symlinked_dir_cache = {} of String => Bool
    # Bundle prompt label => walked path, filled before any bundle is sent.
    @bundle_labels = {} of String => String
    @covered_files = Set(String).new

    def initialize(options : Hash(String, YAML::Any))
      super(options)

      if options.has_key?("ai_provider") && !options["ai_provider"].as_s.empty?
        @provider = options["ai_provider"].as_s
        raw_model = options["ai_model"]?.try(&.as_s) || ""
        @model = if LLM::ACPClient.acp_provider?(@provider)
                   LLM::ACPClient.default_model(@provider, raw_model)
                 else
                   raw_model
                 end
        raw_key = options["ai_key"]?.try(&.as_s)
        @api_key = (raw_key.nil? || raw_key.empty?) ? nil : raw_key
      else
        @provider = "ollama"
        @model = "llama3"
        @api_key = nil
      end

      @max_tokens = LLM.effective_max_tokens(@provider, @model, options["ai_max_token"]?.try(&.as_i) || 0)

      @expanded_base_paths = @base_paths.map { |path| normalized_agent_root(path) }
      @expanded_base_paths.uniq!
      @expanded_base_paths.sort_by!(&.size)
      @expanded_base_paths.reverse!
      # Symlink-resolved twins of the bases, for the containment check in
      # `path_within_base?`. Resolved once here: `realpath` hits the
      # filesystem, and the agent runs the check on every tool call.
      @real_base_paths = @expanded_base_paths.map { |path| resolved_real_path(path) || path }.uniq!
      @use_agentic = options["ai_agent"]?.try { |val| any_to_bool(val) } || false
      @agent_max_steps = options["ai_agent_max_steps"]?.try(&.as_i) || 20
      @native_tool_calling_allowlist = parse_native_tool_allowlist(options["ai_native_tools_allowlist"]?.try(&.as_s))
      @include_sensitive = options["ai_include_sensitive"]?.try { |val| any_to_bool(val) } || false
      @dry_run = options["ai_dry_run"]?.try { |val| any_to_bool(val) } || false
      @agent_tool_cache = {} of String => String
      @agent_tool_cache_order = [] of String
      options[COVERED_FILES_OPTION]?.try(&.as_a?).try &.each { |path| @covered_files << path.as_s }
    end

    def analyze
      event_sink = if LLM::ACPClient.acp_provider?(@provider)
                     ->(msg : String) { logger.sub "➔ #{msg}" }
                   end
      adapter = LLM::AdapterFactory.for(
        @provider,
        @model,
        @api_key,
        event_sink,
        @native_tool_calling_allowlist,
        @max_tokens
      )
      begin
        logger.info "AI Analysis using #{Noir::Redact.url(@provider)} with model #{@model} (max tokens: #{@max_tokens})"

        logger.info "AI dry run previews the classic analysis; the agent loop is not run" if @use_agentic && @dry_run
        if @use_agentic && !@dry_run
          logger.info "AI Agentic workflow is enabled"
          if target = egress_target
            logger.info "The AI agent will send the files it reads to #{target}"
          end
          if analyze_with_agentic_workflow(adapter)
            logger.info "AI Agentic workflow completed (#{@result.size} endpoints)"
            Fiber.yield
            return @result
          end
          logger.warning "AI Agentic workflow failed or did not finalize. Falling back to classic AI analysis."
        end

        target_paths = select_target_paths(adapter)
        if target_paths.empty?
          logger.warning "No files selected for AI analysis"
          return @result
        end

        if @max_tokens > 0 && target_paths.size > 5
          bundled, single = target_paths, [] of String
        else
          # The per-file path sends each file whole, so a file over the
          # token budget goes through bundling, the only path that splits
          # one. The rest stay per-file under --override-analyze-prompt.
          bundled, single = target_paths.partition { |path| @max_tokens > 0 && over_token_budget?(path) }
        end
        bundles = bundled.empty? ? [] of LLM::Bundle : LLM.bundle_files(prepare_files_for_bundling(bundled), @max_tokens)
        announce_egress(bundles, single)
        return @result if @dry_run

        process_bundles_concurrently(bundles, adapter) unless bundles.empty?
        single.each { |path| analyze_file(path, adapter) }

        Fiber.yield
        @result
      ensure
        adapter.close
      end
    end

    # Bytes, not chars: never smaller than the char count `LLM.bundle_files`
    # budgets with, so a file this lets through is never one it would split.
    private def over_token_budget?(path : String) : Bool
      File.size(path) > @max_tokens * 4 * 0.8
    rescue File::Error
      false
    end

    # What is about to leave the machine: printed in full under --ai-dry-run,
    # summarized for a provider that is not on this host. The per-file
    # estimate is bytes/4, the same rule `LLM.estimate_tokens` uses.
    private def announce_egress(bundles : Array(LLM::Bundle), single : Array(String))
      files = (bundles.flat_map(&.paths) + single.map { |path| @base_paths.size > 1 ? path : get_relative_path(base_path, path) }).uniq!.sort!
      tokens = bundles.sum(&.tokens) + single.sum { |path| (File.info?(path).try(&.size) || 0).to_i // 4 }
      summary = "#{files.size} files (~#{tokens} tokens, ~#{bundles.size + single.size} requests)"
      if @dry_run
        logger.info "AI dry run: #{summary} would be sent to #{egress_target || Noir::Redact.url(@provider)}, plus the file-path list (filter) and endpoint URLs (optimizer); nothing was sent"
        files.each { |file| logger.sub "➔ #{file}" }
      elsif target = egress_target
        logger.info "#{summary} will be sent to #{target}"
      end
    end

    # The host source code is sent to, or nil when it stays on this machine.
    # An ACP agent runs locally but forwards prompts to its vendor.
    private def egress_target : String?
      return @provider if LLM::ACPClient.acp_provider?(@provider)
      return (LOCAL_PROVIDERS.includes?(@provider.downcase) ? nil : @provider) unless @provider.includes?("://")
      host = URI.parse(@provider).hostname.to_s
      return if host == "localhost" || (Socket::IPAddress.valid?(host) && Socket::IPAddress.new(host, 0).loopback?)
      host
    rescue URI::Error | Socket::Error
      Noir::Redact.url(@provider)
    end

    private def prepare_files_for_bundling(paths : Array(String)) : Array(Tuple(String, String))
      files = [] of Tuple(String, String)
      paths.each do |path|
        next if File.directory?(path) || File.symlink?(path) || ignore_extensions.includes?(File.extname(path)) || sensitive?(path)

        # The label is what the model echoes back as `file`, so it has to name
        # one file unambiguously. Base-relative is fine for one base; with
        # several, `app.js` could be in any of them, so use the walked path.
        label = @base_paths.size > 1 ? path : get_relative_path(base_path, path)
        @bundle_labels[label] = path
        content = Noir::TextFile.read(path)
        files << {label, content}
      end
      files
    end

    private def process_bundles_concurrently(bundles : Array(LLM::Bundle), adapter : LLM::Adapter)
      total = bundles.size
      worker_count = bundle_worker_count(total)
      logger.debug_sub "AI::Processing #{total} bundle(s) with #{worker_count} worker(s)"

      queue = Channel(Tuple(Int32, LLM::Bundle)).new(DEFAULT_CHANNEL_CAPACITY)

      WaitGroup.wait do |wg|
        # `ensure`, not a trailing statement: if the producer raises
        # mid-send, an unclosed channel leaves every worker parked in
        # `receive?` forever and `WaitGroup.wait` never returns — a silent
        # hang with no output and no exit code. Same reason
        # `Analyzer#parallel_analyze` closes in an `ensure`.
        wg.spawn do
          bundles.each_with_index do |bundle, index|
            queue.send({index, bundle})
          end
        ensure
          queue.close
        end

        worker_count.times do
          wg.spawn do
            loop do
              # The rescue covers the whole iteration, not just
              # `process_bundle`: a worker that dies leaves its share of the
              # bundles unprocessed and, once all of them are gone, parks the
              # producer on a full channel.
              #
              # `item` is hoisted so the rescue can name the files whose
              # coverage was lost. It stays nil when the failure came out of
              # `receive?` itself, where there is no bundle to attribute.
              item = nil
              begin
                item = queue.receive?
                break if item.nil?
                index, bundle = item
                logger.info "Processing bundle #{index + 1}/#{total} (#{bundle.tokens} tokens)"
                process_bundle(bundle, adapter)
              rescue ex : Exception
                if failed = item
                  failed_index, failed_bundle = failed
                  logger.debug "Error processing bundle #{failed_index + 1}: #{ex.message}"
                  record_llm_failure(failed_bundle.paths, "bundle #{failed_index + 1}/#{total} could not be analyzed: #{ex.message}")
                else
                  logger.debug "Error receiving a bundle to process: #{ex.message}"
                end
              end
            end
          end
        end
      end
    end

    # A bundle is a remote LLM call, not a local file read. Spawning one
    # fiber per bundle — the previous behaviour — opened as many
    # simultaneous provider requests as there were bundles: a few hundred
    # on a large repo, which trips rate limits so the retried-and-still-429
    # bundles come back empty and their endpoints silently vanish. Reuse
    # `--concurrency` (the bound the delivery and file analyzers already
    # respect), capped lower because these calls are metered.
    private def bundle_worker_count(total : Int32) : Int32
      # An ACP agent is a single session that serializes prompts anyway
      # (see LLM::ACPClient#request); extra workers would only queue.
      return 1 if LLM::ACPClient.acp_provider?(@provider)

      limit = worker_count.clamp(1, MAX_BUNDLE_WORKERS)
      total < limit ? total : limit
    end

    # A bundle the provider says is over the model's window is re-split and
    # retried instead of lost, so a model the token table doesn't know (or
    # knows wrong) costs a rejected request, not the bundle's endpoints.
    # Providers reject an oversized prompt before inference, so each bundle
    # finding out for itself costs latency, not tokens.
    MAX_RESPLIT_DEPTH = 3

    private def process_bundle(bundle : LLM::Bundle, adapter : LLM::Adapter, depth : Int32 = 0)
      endpoints = call_llm_with_cache(
        kind: "BUNDLE_ANALYZE",
        system_prompt: LLM::SYSTEM_BUNDLE,
        payload: compose_prompt_payload(LLM::PromptOverrides.bundle_analyze_prompt, bundle.content),
        format: LLM::ANALYZE_FORMAT,
        adapter: adapter,
        list_key: "endpoints",
        salvage_for: bundle.paths
      )

      if endpoints
        # An endpoint whose `file` does not resolve falls back to the
        # bundle's file only when there is exactly one; in a multi-file
        # bundle any pick would be a guess, so it gets no code path.
        fallback = bundle.paths.size == 1 ? resolve_reported_file(bundle.paths[0]) : nil
        store_endpoints(endpoints, fallback, bundle.content)
      else
        record_llm_failure(bundle.paths, LLM_NO_RESPONSE_REASON)
      end
    rescue ex : LLM::ContextOverflow
      budget = LLM.overflow_budget(bundle.tokens, ex.limit, ex.used)
      if depth >= MAX_RESPLIT_DEPTH || budget < LLM::MIN_SPLIT_CHARS // 4
        record_llm_failure(bundle.paths, "#{ex.message}, even after re-splitting; set --ai-max-token lower")
        return
      end
      logger.info "Bundle (#{bundle.tokens} tokens) is over the model's context window; re-splitting at #{budget} tokens"
      resplit_bundle(bundle, adapter, budget, depth)
    end

    private def resplit_bundle(bundle : LLM::Bundle, adapter : LLM::Adapter, budget : Int32, depth : Int32)
      files = if part = LLM.split_part(bundle)
                # One part of a split file: re-split that part's text only.
                # Re-reading the file would resend every other part too, once
                # per overflowing part.
                [part]
              else
                # A bundle names its files by prompt label; map back to the
                # walked path.
                prepare_files_for_bundling(bundle.paths.map { |label| @bundle_labels[label]? || label })
              end
      LLM.bundle_files(files, budget).each do |sub|
        process_bundle(sub, adapter, depth + 1)
      end
    end

    private def select_target_paths(adapter : LLM::Adapter) : Array(String)
      locator = CodeLocator.instance
      all_paths = locator.all_files.reject { |path| covered?(path) || sensitive?(path) }

      # A dry run sends nothing, so it previews the unfiltered superset.
      paths = if all_paths.size > 10 && !@dry_run
                logger.debug_sub "AI::Filtering files using LLM"
                egress_target.try { |target| logger.info "Sending #{all_paths.size} file paths to #{target} to select files for analysis" }
                filter_paths_with_llm(all_paths, adapter)
              else
                logger.debug_sub "AI::Analyzing all files"
                get_all_source_files
              end
      paths.reject { |path| covered?(path) }
    end

    # `--ai-scope unmatched`: a file a static analyzer already found an
    # endpoint in is not sent to the provider.
    private def covered?(path : String) : Bool
      !@covered_files.empty? && @covered_files.includes?(Noir::PathScope.expand(path))
    end

    private def filter_paths_with_llm(all_paths : Array(String), adapter : LLM::Adapter) : Array(String)
      user_payload = all_paths.map { |p| "- #{Noir::PathScope.expand(p)}" }.join("\n")

      files = call_llm_with_cache(
        kind: "FILTER",
        system_prompt: LLM::SYSTEM_FILTER,
        payload: compose_prompt_payload(LLM::PromptOverrides.filter_prompt, user_payload),
        format: LLM::FILTER_FORMAT,
        adapter: adapter,
        list_key: "files"
      )

      begin
        selected = (files || [] of JSON::Any).map(&.as_s)

        # Keep only files that were in the listing the model was shown.
        # The listing is the detector-built file set, so it already honours
        # --exclude-path and subtree pruning; a reply naming any other path
        # (an excluded secret, a hallucination) must never reach the
        # provider. The listed form is returned, not the model's echo.
        selected = selected.compact_map { |path| resolve_reported_file(path) }.uniq!

        # Keep only real, in-scope source files. The model sometimes
        # echoes directories or ignorable assets; analyzing those is
        # wasted work and can mask the recall guard below.
        selected = selected.select do |path|
          File.file?(path) &&
            !ignore_extensions.includes?(File.extname(path)) &&
            !sensitive?(path) &&
            path_within_base?(path)
        end

        # Recall guard: an over-aggressive (or empty/garbage) filter
        # would silently zero out AI results — every endpoint in the
        # dropped files becomes a false negative. Fall back to scanning
        # all source files rather than returning nothing.
        if selected.empty?
          logger.debug_sub "AI::Filter returned no usable files; analyzing all source files"
          return get_all_source_files
        end

        selected
      rescue e : Exception
        logger.debug "Error parsing filter response: #{e.message}"
        get_all_source_files
      end
    end

    private def get_all_source_files : Array(String)
      # Pull from the detector-built file_map so subtree pruning and
      # --exclude-path apply here too. The map only contains regular
      # files, so no File.directory? check is needed. Delegate the
      # base-path check to `path_within_base?`, which already handles
      # path expansion — a hand-rolled prefix compare breaks on
      # relative base paths like `.` where the map stores unexpanded
      # paths.
      all_files.select do |path|
        next false if ignore_extensions.includes?(File.extname(path)) || sensitive?(path)
        path_within_base?(path)
      end
    end

    private def analyze_file(path : String, adapter : LLM::Adapter)
      return if File.directory?(path)
      return if !File.exists?(path) || ignore_extensions.includes?(File.extname(path)) || sensitive?(path)

      relative_path = get_relative_path(base_path, path)
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        process_file_content(content, relative_path, path, adapter)
      end
    rescue ex : Exception
      logger.debug "Error processing file: #{path}"
      logger.debug "Error: #{ex.message}"
    end

    private def process_file_content(content : String, relative_path : String, path : String, adapter : LLM::Adapter)
      endpoints = call_llm_with_cache(
        kind: "ANALYZE",
        system_prompt: LLM::SYSTEM_ANALYZE,
        payload: compose_prompt_payload(LLM::PromptOverrides.analyze_prompt, LLM.untrusted(content)),
        format: LLM::ANALYZE_FORMAT,
        adapter: adapter,
        list_key: "endpoints",
        salvage_for: [relative_path]
      )

      if endpoints
        # The path is part of the haystack: file-routed frameworks (Next.js
        # pages, plain PHP) name the route only in the file name.
        store_endpoints(endpoints, path, "#{relative_path}\n#{content}")
      else
        record_llm_failure([relative_path], LLM_NO_RESPONSE_REASON)
      end
    end

    # A failed LLM call used to end here: the empty response failed to parse,
    # a debug line was written, and the analyzer returned its (empty) result
    # through the normal success path. `errors` stayed `[]` and the process
    # exited 0 even under `--strict`, so a provider that answered HTTP 500 to
    # every request was indistinguishable from a clean scan of a codebase with
    # no endpoints — the exact confusion `AnalyzerFailure` exists to prevent.
    #
    # Routed through `Noir::SkippedFiles` rather than raising: bundles are
    # analyzed concurrently and a single failed one must not discard the
    # endpoints the others found. This reports the files that went unread and
    # keeps the rest, which is the same "partial coverage, and here is what is
    # missing" contract the per-file skips already use.
    private def record_llm_failure(paths : Array(String), reason : String)
      paths.each { |path| Noir::SkippedFiles.record("ai", path, reason) }
    end

    private def store_endpoints(endpoints : Array(JSON::Any), default_path : String?, source : String)
      haystack = source.downcase.delete("-_")
      endpoints.each do |ep|
        if endpoint = create_endpoint_from_json(ep, default_path, haystack)
          @result << endpoint
        end
      end
    end

    # `haystack` is the downcased text the model was shown; nil skips the
    # grounding check (agent mode, whose reads are not tracked).
    private def create_endpoint_from_json(ep : JSON::Any, default_path : String?, haystack : String? = nil) : Endpoint?
      url = extract_endpoint_url(ep)
      return unless plausible_endpoint_url?(url)
      if haystack && !Unified.grounded?(url, haystack)
        logger.debug_sub "AI::Dropping endpoint not found in the analyzed source: #{url}"
        return
      end

      method = normalize_http_method(safe_json_string(ep, "method", "GET"))
      path_info = build_path_info(ep, default_path)
      params = extract_params(ep["params"]?)

      details = Details.new(path_info)
      Endpoint.new(url, method, params, details)
    end

    # Reject obviously-hallucinated URLs before they become endpoints.
    # The LLM occasionally returns prose, a "METHOD /path" description, a
    # schema echo, or a stray placeholder instead of a real path; those
    # leak whitespace, control chars, or match a known placeholder token.
    # Real request paths carry none of these signals, so this stays
    # high-precision: it removes false positives without dropping any
    # legitimate endpoint.
    private def plausible_endpoint_url?(url : String) : Bool
      return false unless LLM.clean_token?(url, MAX_ENDPOINT_URL_LENGTH)
      # `lstrip('/')` collapses an all-slash URL to "" — that is the
      # root path ("/"), which is a legitimate endpoint, so only the
      # placeholder-token comparison uses the stripped form.
      bare = url.lstrip('/').downcase
      !PLACEHOLDER_URLS.includes?(bare)
    end

    # A well-formed URL the code never mentions is a hallucination or
    # injected output. The last literal segment must occur in the source,
    # compared case-folded without `-`/`_` and without a `.ext` suffix
    # (`UsersController` grounds `/users`, `getUserProfile` grounds
    # `/user-profile`, `admin.php` grounds `/admin.php`). Prefix-composed
    # routes still pass on their own last segment; `/` and all-placeholder
    # paths have nothing to check and pass. `haystack` must be downcased
    # with `-`/`_` removed.
    # ponytail: convention-generated segments (Rails `resources` -> `/new`,
    # `/edit`) are dropped when the static analyzer did not report them.
    def self.grounded?(url : String, haystack : String) : Bool
      path = url.sub(URL_AUTHORITY_RE, "").split(/[?#]/, 2).first
      literal = path.split('/').reverse_each.find { |seg| !seg.empty? && !seg.matches?(PLACEHOLDER_SEGMENT_RE) }
      return true unless literal
      word = literal.sub(/\.[^.]*\z/, "").presence || literal
      haystack.includes?(word.downcase.delete("-_"))
    end

    # A parameter name is an identifier-ish token. Drop names that carry
    # whitespace/control chars (the model captured a description) or that
    # are absurdly long — both are false-positive params that would
    # otherwise ride along on an otherwise-valid endpoint.
    private def plausible_param_name?(name : String) : Bool
      LLM.clean_token?(name, MAX_PARAM_NAME_LENGTH)
    end

    private def create_param_from_json(param : JSON::Any) : Param?
      case param.raw
      when String
        name = param.as_s.strip
        return unless plausible_param_name?(name)
        Param.new(name, "", "query")
      when Hash
        name = safe_json_string(param, "name", "").strip
        name = safe_json_string(param, "key", "").strip if name.empty?
        name = safe_json_string(param, "param", "").strip if name.empty?
        return unless plausible_param_name?(name)

        param_type = safe_json_string(param, "param_type", "").strip
        param_type = safe_json_string(param, "type", "").strip if param_type.empty?
        value = safe_json_string(param, "value", "")

        Param.new(name, value, normalize_param_type(param_type))
      end
    end

    private def analyze_with_agentic_workflow(adapter : LLM::Adapter) : Bool
      messages = agent_bootstrap_messages
      use_native_tools = adapter.supports_native_tool_calling?
      logger.debug_sub "AI agent mode: #{use_native_tools ? "native tool-calling" : "json action fallback"}"

      @agent_max_steps.times do |step|
        response = if use_native_tools
                     adapter.request_messages_with_tools(messages, LLM::AGENT_TOOLS)
                   else
                     adapter.request_messages(messages, LLM::AGENT_STEP_FORMAT)
                   end
        return false if response.empty?

        logger.debug "AI agent step #{step + 1}:"
        logger.debug_sub response

        append_agent_message(messages, "assistant", response)

        action = parse_agent_action(response)
        unless action
          append_agent_message(messages, "user", "Tool error: invalid action format. Return JSON with action and args.")
          next
        end

        if action[:action] == "finalize"
          logger.verbose "AI agent action: finalize"
          if apply_agent_finalize(action[:args])
            logger.info "AI agent found #{@result.size} potential endpoints" if @is_verbose
            return true
          end

          append_agent_message(messages, "user", "Tool error: finalize must include endpoints array.")
          next
        end

        logger.verbose "AI agent tool call: #{action[:action]}(#{action[:args].to_json})"
        tool_result = run_agent_tool(action[:action], action[:args])
        append_agent_message(messages, "user", "Tool result (#{action[:action]}):\n#{LLM.untrusted(compact_tool_result(tool_result))}")
      end

      false
    rescue ex : Exception
      logger.debug "Agentic workflow failed: #{ex.message}"
      false
    end

    private def agent_bootstrap_messages : Array(Hash(String, String))
      roots = @expanded_base_paths.map { |path| "- #{path}" }.join("\n")
      context = <<-CONTEXT
        Project roots:
        #{roots}

        Start with project exploration and then extract all API endpoints.
        CONTEXT

      [
        {"role" => "system", "content" => LLM::SYSTEM_AGENT},
        {"role" => "user", "content" => compose_prompt_payload(LLM::AGENT_PROMPT, context)},
      ]
    end

    private def parse_agent_action(response : String) : AgentAction?
      parsed = LLM.json_reply(response, "action")
      return if parsed.nil?
      action = parsed["action"].as_s
      args = parsed["args"]? || JSON.parse("{}")
      {action: action, args: args}
    rescue e : Exception
      logger.debug "Failed to parse agent action from LLM response: #{e.message}"
      nil
    end

    private def run_agent_tool(action : String, args : JSON::Any) : String
      cache_key = build_agent_tool_cache_key(action, args)
      if cached = @agent_tool_cache[cache_key]?
        return cached
      end

      result = case action
               when "list_directory"
                 tool_list_directory(args)
               when "read_file"
                 tool_read_file(args)
               when "grep"
                 tool_grep(args)
               when "semantic_search"
                 tool_semantic_search(args)
               else
                 "ERROR: unknown action '#{action}'."
               end
      unless result.empty?
        store_agent_tool_cache(cache_key, result)
      end
      result
    rescue ex : Exception
      "ERROR: #{ex.message}"
    end

    private def build_agent_tool_cache_key(action : String, args : JSON::Any) : String
      "#{action}\n#{args.to_json}"
    end

    private def store_agent_tool_cache(key : String, value : String)
      unless @agent_tool_cache.has_key?(key)
        @agent_tool_cache_order << key
      end
      @agent_tool_cache[key] = value

      overflow = @agent_tool_cache_order.size - AGENT_TOOL_CACHE_MAX_ENTRIES
      return if overflow <= 0

      overflow.times do
        old_key = @agent_tool_cache_order.shift?
        next if old_key.nil?
        @agent_tool_cache.delete(old_key)
      end
    end

    private def compact_tool_result(result : String) : String
      return result if result.size <= AGENT_TOOL_RESULT_MAX_CHARS

      half = AGENT_TOOL_RESULT_MAX_CHARS // 2
      head = result[0, half]? || ""
      tail_start = result.size - half
      tail_start = 0 if tail_start < 0
      tail = result[tail_start, half]? || ""

      <<-TRUNCATED
        NOTE: tool result truncated (#{result.size} chars > #{AGENT_TOOL_RESULT_MAX_CHARS} chars)
        ---HEAD---
        #{head}
        ---TAIL---
        #{tail}
        TRUNCATED
    end

    private def append_agent_message(messages : Array(Hash(String, String)), role : String, content : String)
      messages << {"role" => role, "content" => content}
      prune_agent_messages!(messages)
    end

    private def prune_agent_messages!(messages : Array(Hash(String, String)))
      return if messages.size <= 2

      static_count = 2
      head = messages.first(static_count)
      tail = messages[static_count, messages.size - static_count]

      while tail.size > AGENT_CONTEXT_MAX_DYNAMIC_MESSAGES
        tail.shift
      end

      total_chars = estimate_messages_chars(head) + estimate_messages_chars(tail)
      while total_chars > AGENT_CONTEXT_MAX_CHARS && !tail.empty?
        removed = tail.shift
        total_chars -= estimate_message_chars(removed)
      end

      messages.clear
      messages.concat(head)
      messages.concat(tail)
    end

    private def estimate_messages_chars(messages : Array(Hash(String, String))) : Int32
      messages.sum { |message| estimate_message_chars(message) }
    end

    private def estimate_message_chars(message : Hash(String, String)) : Int32
      (message["role"]? || "").size + (message["content"]? || "").size + 8
    end

    private def apply_agent_finalize(args : JSON::Any) : Bool
      endpoint_json = args["endpoints"]?
      return false if endpoint_json.nil?

      added = 0
      endpoint_json.as_a.each do |ep|
        # No file the agent read is known here, so an unresolved `file`
        # leaves the endpoint without a code path rather than a fake one.
        if endpoint = create_endpoint_from_json(ep, nil)
          @result << endpoint
          added += 1
        end
      end

      confidence = safe_json_int(args, "confidence", -1)
      summary = safe_json_string(args, "summary", "")
      logger.info "AI agent finalized #{added} endpoints (confidence=#{confidence})" if confidence >= 0
      logger.verbose "AI agent summary: #{summary}" unless summary.empty?

      true
    rescue ex : Exception
      logger.debug "Error while finalizing agent output: #{ex.message}"
      false
    end

    private def tool_list_directory(args : JSON::Any) : String
      path = safe_json_string(args, "path", ".")
      max_depth = safe_json_int(args, "max_depth", 3)
      max_depth = 1 if max_depth < 1
      max_depth = AGENT_MAX_DEPTH if max_depth > AGENT_MAX_DEPTH

      roots = resolve_agent_roots(path)
      return "ERROR: path '#{path}' is outside base paths or does not exist." if roots.empty?

      lines = [] of String
      roots.each do |root|
        if File.directory?(root)
          lines << "ROOT #{agent_relative_path(root)}"
          walk_directory_tree(root, 0, max_depth, lines)
        else
          lines << "[F] #{agent_relative_path(root)}"
        end
        break if lines.size >= AGENT_TOOL_MAX_LINES
      end

      summarize_lines(lines)
    end

    private def walk_directory_tree(current : String, depth : Int32, max_depth : Int32, lines : Array(String))
      return if depth > max_depth || lines.size >= AGENT_TOOL_MAX_LINES

      entries = Dir.children(current).sort
      entries.each do |entry|
        break if lines.size >= AGENT_TOOL_MAX_LINES

        full_path = File.join(current, entry)
        indent = "  " * depth

        begin
          next if File.symlink?(full_path)
          # A directory is tested too, so `--exclude-path secrets/` hides the
          # subtree rather than listing it and then filtering each file out
          # of it one by one.
          next if excluded_path?(full_path)

          if File.directory?(full_path)
            lines << "#{indent}[D] #{agent_relative_path(full_path)}/"
            walk_directory_tree(full_path, depth + 1, max_depth, lines) if depth < max_depth
          else
            next if ignore_extensions.includes?(File.extname(full_path)) || sensitive?(full_path)
            lines << "#{indent}[F] #{agent_relative_path(full_path)}"
          end
        rescue ex : Exception
          lines << "#{indent}[E] #{agent_relative_path(full_path)} (#{ex.message})"
        end
      end
    end

    private def tool_read_file(args : JSON::Any) : String
      path = safe_json_string(args, "path", "")
      return "ERROR: path is required." if path.empty?

      resolved = resolve_agent_single_path(path)
      return "ERROR: file '#{path}' is outside base paths or does not exist." if resolved.nil?
      return "ERROR: file '#{path}' is excluded by --exclude-path." if excluded_path?(resolved)
      # The real path too: an in-base `config.js -> .env` link is allowed through.
      if sensitive?(resolved) || sensitive?(resolved_real_path(resolved) || resolved)
        return "ERROR: file '#{path}' is withheld as a credentials file (--ai-include-sensitive to allow)."
      end
      return "ERROR: '#{path}' is a directory. Use list_directory instead." if File.directory?(resolved)

      content = Noir::TextFile.read(resolved)
      return "FILE #{agent_relative_path(resolved)}\n#{content}" if content.bytesize <= AGENT_MAX_READ_BYTES

      half = AGENT_MAX_READ_BYTES // 2
      head = content[0, half]? || ""
      tail_start = content.size - half
      tail_start = 0 if tail_start < 0
      tail = content[tail_start, half]? || ""

      <<-TRUNCATED
        FILE #{agent_relative_path(resolved)}
        NOTE: truncated large file (#{content.bytesize} bytes > #{AGENT_MAX_READ_BYTES} bytes)
        ---HEAD---
        #{head}
        ---TAIL---
        #{tail}
        TRUNCATED

    rescue ex : Exception
      "ERROR: failed to read file '#{path}' (#{ex.message})"
    end

    private def tool_grep(args : JSON::Any) : String
      pattern = safe_json_string(args, "pattern", "")
      return "ERROR: pattern is required." if pattern.empty?

      path = safe_json_string(args, "path", ".")
      file_pattern = safe_json_string(args, "file_pattern", AGENT_DEFAULT_FILE_PATTERN)

      collect_grep_results(pattern, path, file_pattern)
    end

    private def tool_semantic_search(args : JSON::Any) : String
      query = safe_json_string(args, "query", "")
      return "ERROR: query is required." if query.empty?

      keywords = query.downcase.split(/[^a-z0-9_]+/).select { |token| token.size >= 3 }.uniq!
      keywords = keywords.first(8)
      return "ERROR: query did not provide useful keywords." if keywords.empty?

      pattern = keywords.map { |keyword| Regex.escape(keyword) }.join("|")
      result = collect_grep_results(pattern, ".", AGENT_DEFAULT_FILE_PATTERN)
      "QUERY_TERMS: #{keywords.join(", ")}\n#{result}"
    end

    private def collect_grep_results(pattern : String, path : String, file_pattern : String) : String
      roots = resolve_agent_roots(path)
      return "ERROR: path '#{path}' is outside base paths or does not exist." if roots.empty?

      regex = Regex.new(pattern)
      matches = [] of String

      roots.each do |root|
        glob = if File.directory?(root)
                 "#{escape_glob_path(root)}/**/#{file_pattern}"
               else
                 escape_glob_path(root)
               end

        Dir.glob(glob).each do |file_path|
          break if matches.size >= AGENT_TOOL_MAX_MATCHES
          next if File.directory?(file_path) || File.symlink?(file_path)
          next if ignore_extensions.includes?(File.extname(file_path)) || sensitive?(file_path)
          next unless path_within_base?(file_path)
          next if excluded_path?(file_path)

          begin
            line_number = 0
            File.open(file_path, "r", encoding: "utf-8", invalid: :skip) do |file|
              file.each_line do |line|
                line_number += 1
                next unless regex_matches_bounded?(regex, line)

                snippet = line.strip
                snippet = snippet[0, AGENT_GREP_SNIPPET_MAX_CHARS] if snippet.size > AGENT_GREP_SNIPPET_MAX_CHARS
                matches << "#{agent_relative_path(file_path)}:#{line_number}: #{snippet}"
                break if matches.size >= AGENT_TOOL_MAX_MATCHES
              end
            end
          rescue ex : Exception
            logger.debug "Error processing file for grep '#{file_path}': #{ex.message}"
          end
        end
      end

      return "NO_MATCH" if matches.empty?
      summarize_lines(matches, AGENT_TOOL_MAX_MATCHES)
    rescue ex : Regex::Error
      "ERROR: invalid regex pattern (#{ex.message})"
    end

    private def compose_prompt_payload(prompt_template : String, content : String) : String
      return prompt_template if content.empty?
      "#{prompt_template.rstrip}\n#{content}"
    end

    private def resolve_agent_roots(path : String) : Array(String)
      normalized = path.strip
      normalized = "." if normalized.empty?

      if normalized == "."
        return @expanded_base_paths.select { |root| File.exists?(root) }
      end

      if normalized.starts_with?("/")
        candidate = Noir::PathScope.expand(normalized)
        return [] of String unless File.exists?(candidate) && path_within_base?(candidate)
        return [candidate]
      end

      roots = [] of String
      @expanded_base_paths.each do |base|
        candidate = File.expand_path(normalized, base)
        if File.exists?(candidate) && path_within_base?(candidate)
          roots << candidate
        end
      end
      roots.uniq
    end

    private def resolve_agent_single_path(path : String) : String?
      resolve_agent_roots(path).first?
    end

    # Containment gate for every agent file tool. The agent picks these
    # paths from LLM output, and the LLM is steered by the source tree being
    # scanned, so "stay inside the scan base" is a boundary an untrusted repo
    # gets to push on.
    #
    # `File.expand_path` is purely lexical — it folds `..` and makes the path
    # absolute but never follows a link. A checked-out repo containing
    # `notes -> /home/user/.ssh/id_rsa` therefore passed as an in-base path,
    # and `read_file` shipped the target's contents to the LLM provider.
    # (The tree walk, the grep and the bundling path all skip symlinks
    # already; these two entry points were the gap.)
    #
    # So resolve both sides and require containment of the *real* path. A
    # base that is itself reached through a link (`/tmp` -> `/private/tmp` on
    # macOS) still matches, because `@real_base_paths` went through the same
    # resolution. The lexical check stays as the first gate: it rejects the
    # plain `../../etc/passwd` case without touching the filesystem.
    #
    # Public rather than private so the rule can be asserted directly:
    # reaching it through a live LLM round trip is not a test.
    def path_within_base?(path : String) : Bool
      expanded = Noir::PathScope.expand(path)
      return false unless contained_in?(expanded, @expanded_base_paths)
      {% if flag?(:windows) %}
        # `File.symlink?` is false for a directory junction (`mklink /J`, a
        # mount-point reparse point that needs no privilege to create), so
        # the link shortcut below would never resolve one. Resolve every
        # path that exists; a missing one has nothing to read.
        return true unless File.exists?(expanded)
      {% else %}
        return true unless File.symlink?(expanded) || symlinked_ancestor?(expanded)
      {% end %}

      real = resolved_real_path(expanded)
      return false if real.nil?
      contained_in?(real, @real_base_paths)
    end

    private def contained_in?(path : String, bases : Array(String)) : Bool
      bases.any? do |base|
        path == base || path.starts_with?(base == File::SEPARATOR ? base : "#{base}/")
      end
    end

    # Only the part of the path below the base can be a planted link, so the
    # walk stops at the base rather than at `/` — that keeps the stat count
    # proportional to the repo-relative depth and leaves a symlinked base
    # (already accounted for in `@real_base_paths`) out of it. Per-directory
    # answers are memoized because grep runs this once per candidate file and
    # the ancestors repeat for every file in a directory.
    private def symlinked_ancestor?(path : String) : Bool
      current = File.dirname(path)
      while current != "/" && current != "." && !current.empty?
        return false if @expanded_base_paths.includes?(current)
        return true if @symlinked_dir_cache.fetch(current) { |dir| @symlinked_dir_cache[dir] = File.symlink?(dir) }
        parent = File.dirname(current)
        break if parent == current
        current = parent
      end
      false
    end

    private def resolved_real_path(path : String) : String?
      File.realpath(path)
    rescue ex : Exception
      logger.debug "Failed to resolve real path for '#{path}': #{ex.message}"
      nil
    end

    private def agent_relative_path(path : String) : String
      expanded = Noir::PathScope.expand(path)
      @expanded_base_paths.each do |base|
        return "." if expanded == base

        prefix = base == File::SEPARATOR ? base : "#{base}/"
        return expanded.sub(prefix, "") if expanded.starts_with?(prefix)
      end
      expanded
    end

    private def normalized_agent_root(path : String) : String
      expanded = Noir::PathScope.expand(path)
      expanded == File::SEPARATOR ? expanded : expanded.rstrip('/')
    end

    private def summarize_lines(lines : Array(String), limit : Int32 = AGENT_TOOL_MAX_LINES) : String
      return "EMPTY" if lines.empty?
      return lines.join("\n") if lines.size <= limit

      shown = lines[0, limit]
      "#{shown.join("\n")}\n...TRUNCATED #{lines.size - limit} lines"
    end

    private def extract_endpoint_url(ep : JSON::Any) : String
      url = safe_json_string(ep, "url", "").strip
      url = safe_json_string(ep, "path", "").strip if url.empty?

      if !url.empty? && !url.starts_with?("/") && !url.includes?("://")
        "/#{url}"
      else
        url
      end
    end

    private def build_path_info(ep : JSON::Any, default_path : String?) : PathInfo?
      path = resolve_reported_file(safe_json_string(ep, "file", "")) || default_path
      return unless path
      PathInfo.new(path, safe_json_int_or_nil(ep, "line"))
    rescue e : Exception
      logger.debug "Failed to build path info from LLM response: #{e.message}"
      default_path.try { |fallback| PathInfo.new(fallback) }
    end

    # The model's `file` is untrusted — it names whatever the scanned code
    # steered it to, and `--ai-context` later reads that path into the
    # report. Accept it only as a file the detector registered (inside a
    # base, past --exclude-path), and return the as-walked spelling the
    # static analyzers report. A bundle label maps straight to its file;
    # any other relative name is resolved against each base and rejected
    # when it names a file in more than one.
    private def resolve_reported_file(file : String) : String?
      file = file.strip
      return if file.empty?
      if labelled = @bundle_labels[file]?
        return labelled
      end

      matches = @expanded_base_paths.compact_map do |base|
        walked = walked_path?(Noir::PathScope.expand(File.expand_path(file, base)))
        walked if walked && path_within_base?(walked)
      end
      matches.uniq!
      matches.size == 1 ? matches[0] : nil
    end

    private def extract_params(params_json : JSON::Any?) : Array(Param)
      return [] of Param if params_json.nil?

      params = [] of Param
      begin
        params_json.as_a.each do |param|
          if normalized = create_param_from_json(param)
            params << normalized
          end
        end
      rescue ex : Exception
        logger.debug "Error parsing params from LLM response: #{ex.message}"
      end
      params
    end

    private def normalize_http_method(method : String) : String
      normalized = method.upcase
      VALID_METHODS.includes?(normalized) ? normalized : "GET"
    end

    private def normalize_param_type(param_type : String) : String
      normalized = param_type.downcase
      VALID_PARAM_TYPES.includes?(normalized) ? normalized : "query"
    end

    private def safe_json_string(data : JSON::Any, key : String, default : String = "") : String
      value = data[key]?
      return default if value.nil?
      value.as_s
    rescue e : Exception
      logger.debug "Failed to cast JSON value to String: #{e.message}"
      default
    end

    private def safe_json_int(data : JSON::Any, key : String, default : Int32 = 0) : Int32
      value = data[key]?
      return default if value.nil?
      value.as_i
    rescue e : Exception
      logger.debug "Failed to cast JSON value to Int32: #{e.message}"
      default
    end

    private def safe_json_int_or_nil(data : JSON::Any, key : String) : Int32?
      value = data[key]?
      return if value.nil?
      value.as_i
    rescue e : Exception
      logger.debug "Failed to cast JSON value to Int32: #{e.message}"
      nil
    end

    private def parse_native_tool_allowlist(raw : String?) : Array(String)?
      return if raw.nil? || raw.strip.empty?
      tokens = raw.split(",").map(&.strip.downcase).reject(&.empty?).uniq!
      tokens.empty? ? nil : tokens
    end

    # Returns the reply's `list_key` array, or nil when the call failed or the
    # reply is not a JSON object (truncated, prose, `null`) or its list is
    # not an array. Only a usable reply is cached: a stored truncation would be
    # replayed on every later scan as "no endpoints" without another request.
    #
    # With `salvage_for`, a reply cut off mid-list still yields the complete
    # items before the cut; those files are reported as partly analyzed.
    private def call_llm_with_cache(kind : String, system_prompt : String, payload : String, format : String, adapter : LLM::Adapter, list_key : String, salvage_for : Array(String)? = nil) : Array(JSON::Any)?
      # Fold the system prompt into the cache key. The remote request
      # is driven by both the system and user prompts, so keying on the
      # payload alone would replay a stale response after a system-prompt
      # change (e.g. tightened FP/FN guidance) until the user manually
      # cleared the cache. The system prompt is only mixed into the key,
      # never sent twice.
      disk_key = LLM::Cache.key(@provider, @model, kind, format, "#{system_prompt}\n#{payload}")

      # A cached entry an older version stored without this check may be
      # unusable too; asking again beats replaying it.
      if (cached = LLM::Cache.fetch(disk_key)) && (items = reply_list(cached, list_key))
        logger.debug "AI #{kind} response (cached):"
        logger.debug_sub cached
        return items
      end

      # Each request carries its full system + user prompt; nothing is
      # chained between files or bundles.
      response = if kind == "BUNDLE_ANALYZE"
                   adapter.request_bundle(system_prompt, payload, format)
                 else
                   adapter.request_with_context(system_prompt, payload, format)
                 end
      logger.debug "AI #{kind} response:"
      logger.debug_sub response

      # The adapters return "" when the remote call fails (HTTP error,
      # timeout) and have already warned about it.
      return if response.empty?

      items = reply_list(response, list_key)
      if items
        LLM::Cache.store(disk_key, response)
      elsif salvage_for && (items = LLM.salvage_list(response, list_key))
        record_llm_failure(salvage_for, "the AI reply was incomplete; only the #{items.size} complete item(s) before the break were kept")
      else
        STDERR.puts "WARNING: AI reply is not a JSON object with an \"#{list_key}\" array: #{LLM::HttpTransport.truncate_error_snippet(response)}"
      end
      items
    end

    # `{}` or a null list is the model saying "nothing here". Any other
    # object without the list (`{"error": ...}`, `{"routes": [...]}`) is not
    # an answer, and is reported rather than cached as zero endpoints.
    private def reply_list(response : String, key : String) : Array(JSON::Any)?
      object = LLM.json_reply(response, key)
      return if object.nil?
      list = object[key]?
      return [] of JSON::Any if list.nil? || list.raw.nil?
      list.as_a?
    end

    def ignore_extensions
      IGNORE_EXTENSIONS
    end

    # The one gate on credentials files leaving the machine; see SENSITIVE_FILE.
    def sensitive?(path : String) : Bool
      !@include_sensitive && File.basename(path).matches?(SENSITIVE_FILE)
    end

    def max_tokens
      @max_tokens
    end
  end
end
