require "./analyzers/**"
require "./analyzers/file_analyzers/*"
require "../miniparsers/extraction_result_cache"

def initialize_analyzers(logger : NoirLogger)
  # Initializing analyzers
  analyzers = {} of String => Proc(Hash(String, YAML::Any), Array(Endpoint))

  # The registry is read off the analyzer classes themselves — each one
  # names its tech with `analyzer_for` — rather than from a hand-maintained
  # list. That list was a second place every new analyzer had to be added,
  # and forgetting it produced no error and no failing spec: the integrity
  # spec compares *registered* analyzers against the catalog, so a class that
  # was never registered was invisible to it. An analyzer now joins the
  # registry by existing.
  #
  # The `Analyzer::` filter is the production contract; `FileAnalyzer` (run
  # separately, via its own hooks) and the `AnalyzerExample` template sit
  # outside the namespace. Shared base classes are `abstract`, so they are
  # excluded — and any concrete class under `Analyzer::` that forgets
  # `analyzer_for` is a compile error here rather than a silent no-op.
  #
  # Sorted by class name so the order is a property of the source rather
  # than of `require "./analyzers/**"`. Order is not load-bearing: the techs
  # actually run are chosen by detection, each analyzer is spawned
  # concurrently, and the optimizer sorts endpoints before output.
  {% for klass in Analyzer.all_subclasses.select { |sub| !sub.abstract? && sub.name.starts_with?("Analyzer::") }.sort_by(&.name) %}
    analyzers[{{ klass }}.tech_name] = ->(options : Hash(String, YAML::Any)) do
      instance = {{ klass }}.new(options)
      instance.analyze
    end
  {% end %}

  logger.debug "#{analyzers.size} Analyzers initialized"
  analyzers.each do |key, _|
    logger.debug_sub "#{key} initialized"
  end
  analyzers
end

# CFML frameworks that own their application's route table.
CFML_FRAMEWORK_TECHS = Set{
  "cfml_taffy",
  "cfml_coldbox",
  "cfml_wheels",
  "cfml_fw1",
}

def filter_redundant_generic_techs(techs : Array(String)) : Array(String)
  filtered = techs.dup

  # NOTE: `php_pure` is deliberately NOT dropped when a framework is
  # present. It used to be, because it emitted every `.php` file in the
  # tree as an endpoint and drowned framework scans in paths that are not
  # web-reachable (`/config/app.php`, `/app/Models/User.php`). That was a
  # workaround for a defect in the analyzer, and it cost real findings: a
  # legacy script inside the document root — `public/upload.php` beside a
  # Laravel app — vanished with it. `Analyzer::Php::Php` now resolves URLs
  # against the document root, so the noise is gone at the source and the
  # generic analyzer can run alongside the framework one. See #2358.
  #
  # `cfml_pure` used to be dropped for the same reason and paid the same
  # price — the `remote` methods on a ColdBox app's proxy components are
  # HTTP-callable whatever framework fronts them, and no framework
  # analyzer emits them. It now runs in components-only mode instead (see
  # `CFML_FRAMEWORK_TECHS` below), which keeps those and still leaves the
  # `.cfm` page surface to the framework that owns it.

  # Lumen and Laravel share enough surface (Illuminate namespaces, the `routes/`
  # convention) that the Laravel detector also fires on Lumen projects. When
  # Lumen is the actual framework, the Laravel signal is just noise.
  if filtered.includes?("php_lumen") && filtered.includes?("php_laravel")
    filtered.reject!("php_laravel")
  end

  # Bandit hosts the same `Plug.Router` modules the Plug analyzer
  # already understands, so both detectors fire on a Bandit project.
  # When both are present, the Bandit signal is the more specific one
  # (it tells you which HTTP server is actually serving the routes);
  # keep it and drop the redundant Plug entry so endpoints aren't
  # extracted twice with two different technology tags. The Phoenix
  # analyzer is unaffected — it owns the Phoenix.Router DSL.
  if filtered.includes?("elixir_bandit") && filtered.includes?("elixir_plug")
    filtered.reject!("elixir_plug")
  end

  # Jetzig and Tokamak are both built on top of http.zig (httpz), so a
  # project that vendors either framework's source also carries the
  # `@import("httpz")` / `.httpz` dependency markers the httpz detector
  # keys on. When the more specific framework is present it owns the
  # routing DSL; keep it and drop the redundant httpz entry so the httpz
  # analyzer doesn't also scan the framework's internals.
  if filtered.includes?("zig_httpz") && (filtered.includes?("zig_jetzig") || filtered.includes?("zig_tokamak"))
    filtered.reject!("zig_httpz")
  end

  # Drupal and Magento are both built on Symfony components, so their
  # composer.json pulls in `symfony/*` and the Symfony detector fires on
  # every Drupal/Magento project. Those apps do not expose Symfony-native
  # routes (Drupal uses `*.routing.yml`, Magento uses `webapi.xml` /
  # `routes.xml`), and the Symfony YAML analyzer would otherwise
  # double-parse Drupal routing files that happen to sit under a `config`
  # path. Keep the specific CMS analyzer and drop the redundant Symfony
  # entry so endpoints aren't extracted twice under a misleading tech tag.
  if filtered.includes?("php_symfony") && (filtered.includes?("php_drupal") || filtered.includes?("php_magento"))
    filtered.reject!("php_symfony")
  end

  # NOTE: do not add "generic stdlib analyzer is redundant when framework
  # X is present" rules here. `techs` is a flat, repo-wide list with no
  # path granularity, so a framework detected anywhere suppresses the
  # generic analyzer *everywhere*. In a monorepo that silently drops real
  # attack surface: a standalone `net/http` admin listener exposing
  # /debug/pprof next to a Gin API, or a standalone Starlette service next
  # to a FastAPI one. Framework-vs-framework rules above are safe because
  # both analyzers target the same routing DSL; framework-vs-stdlib rules
  # are not. Scoping this correctly needs a per-tech path map from the
  # detector (the detect loop does know the file), not a global list.
  filtered
end

def analysis_endpoints(options : Hash(String, YAML::Any), techs, logger : NoirLogger)
  result = [] of Endpoint
  file_analyzer = FileAnalyzer.new options
  logger.info "Initializing analyzers"

  # Drop process-wide extraction memos from any previous scan (diff mode
  # / repeated library use) so fingerprints cannot serve stale tables.
  Noir::ExtractionResultCache.clear_all

  analyzer = initialize_analyzers logger

  logger.verbose "Loaded #{analyzer.size} analyzers"

  logger.info "Analysis Started"
  logger.sub "➔ Code Analyzer: #{techs.size} in use"

  if (!options["ai_provider"].to_s.empty?) && ((!options["ai_model"].to_s.empty?) || LLM::ACPClient.acp_provider?(options["ai_provider"].to_s))
    provider = options["ai_provider"].to_s
    raw_model = options["ai_model"].to_s
    model = if LLM::ACPClient.acp_provider?(provider)
              LLM::ACPClient.default_model(provider, raw_model)
            else
              raw_model
            end
    logger.sub "➔ AI Analyzer: Server=#{provider}, Model=#{model}"
    techs << "ai"
  end

  # Run tech analyzers concurrently to avoid long stalls from a single analyzer
  selected_techs = filter_redundant_generic_techs(techs).select { |t| analyzer.has_key?(t) }

  # A CFML framework owns the `.cfm` page surface, so the generic analyzer
  # narrows to the half no framework analyzer covers: `access="remote"`
  # methods on `.cfc` components.
  if selected_techs.includes?("cfml_pure") && selected_techs.any? { |tech| CFML_FRAMEWORK_TECHS.includes?(tech) }
    options[Analyzer::Cfml::Pure::COMPONENTS_ONLY_OPTION] = YAML::Any.new(true)
  end

  mutex = Mutex.new

  # Pre-build extension index synchronously to avoid concurrent mutation in multiple threads/fibers
  CodeLocator.instance.build_extension_index

  WaitGroup.wait do |wg|
    selected_techs.each do |tech|
      wg.spawn do
        begin
          logger.debug "Analyzer[#{tech}] start"
          endpoints = analyzer[tech].call(options)
          # Set technology on each endpoint using map to handle struct copy
          endpoints_with_tech = endpoints.map do |ep|
            details = ep.details
            details.technology = tech
            ep.details = details
            ep
          end
          mutex.synchronize { result.concat(endpoints_with_tech) }
          logger.debug "Analyzer[#{tech}] done (#{endpoints.size})"
        rescue e
          logger.warning "Analyzer[#{tech}] failed: #{e.message}"
        end
      end
    end
  end

  # `hooks_count` reports only the hooks that can produce something for
  # this scan: without `-u/--url` the url-matching hooks sit out and the
  # url-independent ones (graphql operation documents) still run. This used
  # to be `unless options["url"].empty?`, which skipped the whole
  # FileAnalyzer — and with it GraphQL operations — on every default scan.
  file_analyzer_hooks = file_analyzer.hooks_count
  if file_analyzer_hooks > 0
    logger.sub "➔ File-based Analyzer: #{file_analyzer_hooks} hook#{'s' unless file_analyzer_hooks == 1} in use"
    result = result + file_analyzer.analyze
  end

  logger.info "Found #{result.size} endpoints"
  result
end
