require "./analyzers/**"
require "./analyzers/file_analyzers/*"
require "../miniparsers/extraction_result_cache"
require "../techs/techs"

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

# Whether the generic CFML analyzer should narrow to components-only mode.
#
# This is a *narrowing*, not a supersede, which is why it stays here rather
# than moving to the catalog's `:supersedes` alongside the four
# framework-shadows-framework rules. A CFML framework owns the `.cfm` page
# surface, so dropping `cfml_pure` outright would lose the half no framework
# analyzer covers — the `access="remote"` methods on a ColdBox app's proxy
# components, which are HTTP-callable whatever framework fronts them.
# Narrowing keeps those and still leaves the page surface to its owner.
#
# Extracted from `analysis_endpoints` so it can be tested at all: in place
# it sat inside the function that runs every analyzer.
def cfml_components_only?(selected_techs : Array(String)) : Bool
  selected_techs.includes?("cfml_pure") &&
    selected_techs.any? { |tech| CFML_FRAMEWORK_TECHS.includes?(tech) }
end

# Drops techs that another detected tech supersedes. The rules live on the
# superseding tech's catalog entry as `:supersedes`; see the doc on
# `NoirTechs::SUPERSEDES` for what belongs there and — more importantly —
# what must never be added.
#
# Presence is evaluated against the *input* list rather than the array being
# filtered, so the result no longer depends on the order the rules happen to
# be written in. `SUPERSEDES` chains are rejected by the tech-registry
# integrity spec, which keeps that equivalence true.
def filter_redundant_generic_techs(techs : Array(String)) : Array(String)
  drop = Set(String).new
  techs.each { |tech| NoirTechs.supersedes(tech).each { |target| drop << target } }
  techs.reject { |tech| drop.includes?(tech) }
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

  if cfml_components_only?(selected_techs)
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
