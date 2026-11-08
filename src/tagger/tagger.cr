require "./taggers/*"
require "./framework_taggers/**"
require "./rule_tagger"
require "../models/tagger"
require "../models/framework_tagger"

module NoirTaggers
  # One tagger, as declared by its class's `Noir::TaggerFor` annotation.
  #
  # `runner` is deliberately not a field. Storing the class object erases
  # `self.target_techs` — it lives on `FrameworkTagger`, not on `Tagger` —
  # so every read would need a cast back. The two macro-generated `case`
  # dispatchers below resolve per concrete class instead, the same shape
  # `Noir::OutputFormats.render` uses.
  record Entry, key : String, name : String, desc : String, framework : Bool, order : Int32

  # Every annotated tagger, in `order`. Derived from the classes, so a
  # tagger joins the registry by existing: the two hand-maintained hash
  # literals this replaces were a second place to remember, where
  # forgetting produced no error and no failing spec — just a tagger that
  # never ran. The YAML rules in `src/tagger/rules/` join the same list
  # (`NoirTagRules::BUILTIN`) and sort in among the classes by `order`.
  ENTRIES = begin
    classes = {% begin %}
      [
        {% for tagger in Tagger.all_subclasses.select(&.annotation(Noir::TaggerFor)) %}
          {% ann = tagger.annotation(Noir::TaggerFor) %}
          Entry.new({{ ann[:key] }}, {{ ann[:name] }}, {{ ann[:desc] }},
            {{ tagger.ancestors.includes?(FrameworkTagger) }}, {{ ann[:order] }}),
        {% end %}
      ] of Entry
    {% end %}
    rules = NoirTagRules::BUILTIN.map { |rule| Entry.new(rule.key, rule.name, rule.summary, false, rule.order) }
    (classes + rules).sort_by! { |entry| {entry.order, entry.key} }
  end

  PLAIN_ENTRIES     = ENTRIES.reject(&.framework)
  FRAMEWORK_ENTRIES = ENTRIES.select(&.framework)

  # The framework taggers that emit the `auth` tag. They share one naming
  # convention, `{framework}_auth`, and a spec pins it.
  AUTH_ENTRIES = FRAMEWORK_ENTRIES.select(&.key.ends_with?("_auth"))

  # Whether a `--use-taggers` list runs at least one tagger that can emit
  # the `auth` tag.
  def self.auth_tagging?(use_taggers : String) : Bool
    requested = use_taggers.split(",").map(&.strip.downcase)
    requested.includes?("all") || AUTH_ENTRIES.any? { |entry| requested.includes?(entry.key) }
  end

  # Instantiates the tagger `key` names, or nil when nothing claims it.
  def self.build(key : String, options : Hash(String, YAML::Any)) : Tagger?
    {% begin %}
      case key
      {% for tagger in Tagger.all_subclasses.select(&.annotation(Noir::TaggerFor)) %}
      when {{ tagger.annotation(Noir::TaggerFor)[:key] }}
        {{ tagger }}.new(options)
      {% end %}
      else
        NoirTagRules.find(key).try { |rule| RuleTagger.new(options, rule) }
      end
    {% end %}
  end

  # Techs a framework tagger declares an interest in; empty for plain
  # taggers, which run against every endpoint.
  def self.target_techs(key : String) : Array(String)
    {% begin %}
      case key
      {% for tagger in Tagger.all_subclasses
                         .select { |sub| sub.annotation(Noir::TaggerFor) && sub.ancestors.includes?(FrameworkTagger) } %}
      when {{ tagger.annotation(Noir::TaggerFor)[:key] }}
        {{ tagger }}.target_techs
      {% end %}
      else
        [] of String
      end
    {% end %}
  end

  def self.available_tagger_names : Array(String)
    names = ENTRIES.map(&.key)
    names << "all"
    names.sort
  end

  # The `--tagger-rules` rules for this scan. Loading raises
  # `NoirTagRules::RuleError` on a bad file or a key some tagger already has.
  def self.user_rules(options : Hash(String, YAML::Any)) : Array(NoirTagRules::Rule)
    NoirTagRules.user_rules(options, ENTRIES.map(&.key).to_set)
  end

  # `extra_keys` are the user rules' keys, which are valid `--use-taggers`
  # values for this scan only.
  def self.unknown_tagger_names(use_taggers : String, extra_keys : Array(String) = [] of String) : Array(String)
    requested = use_taggers.split(",").map(&.strip).reject(&.empty?)
    valid_names = available_tagger_names + extra_keys
    # Case-insensitive match: canonical names in `valid_names` are
    # lowercase. `--use-taggers Hunt` and `--use-taggers HUNT` were
    # rejected pre-fix even though the user clearly intended `hunt`;
    # `noir list taggers` doesn't communicate that the names are
    # case-sensitive either.
    requested.reject { |name| valid_names.includes?(name.downcase) }
  end

  def self.validate_tagger_names!(use_taggers : String, extra_keys : Array(String) = [] of String)
    unknown = unknown_tagger_names(use_taggers, extra_keys)
    return if unknown.empty?

    raise ArgumentError.new("Unknown tagger(s): #{unknown.join(", ")}")
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers : String)
    custom_rules = user_rules(options)
    validate_tagger_names!(use_taggers, custom_rules.map(&.key))

    # Parsing use_taggers — normalize to lowercase so case-insensitive
    # input matches the lowercase canonical tagger names. Validation
    # (`validate_tagger_names!` above) uses the same shape.
    use_taggers_arr = use_taggers.split(",").map(&.strip.downcase)
    is_all = use_taggers_arr.includes?("all")

    logger = NoirLogger.from_options(options)

    # The registry key IS the tagger's `name` (`Tagger#initialize` reads it
    # back off the class), so an unselected tagger can be skipped without
    # constructing it — each `new` builds a logger and resolves options. Run
    # the selected ones in registry order, which is user-visible: tags are
    # appended in the order taggers run and nothing sorts them before
    # output. A single tagger raising must not abort the rest of the pass
    # (here or in the framework pass below) — degrade to "this tagger failed".
    #
    # `--tagger-rules` rules always run (passing the flag is the opt-in) and
    # sort in among the selected ones by `order`. They have no spec to keep
    # their examples honest, so a wrong example is a warning here instead.
    custom_rules.each do |rule|
      NoirTagRules.example_failures(rule).each do |failure|
        logger.warning "Tag rule '#{rule.key}' (#{rule.source}) example #{failure}"
      end
    end

    runs = PLAIN_ENTRIES.select { |entry| is_all || use_taggers_arr.includes?(entry.key) }
      .map { |entry| {entry.order, entry.key, nil.as(NoirTagRules::Rule?)} }
    runs.concat(custom_rules.map { |rule| {rule.order, rule.key, rule.as(NoirTagRules::Rule?)} })
    runs.sort_by! { |(order, key, _)| {order, key} }

    runs.each do |(_, key, rule)|
      tagger = rule ? RuleTagger.new(options, rule) : build(key, options)
      tagger.try(&.perform(endpoints))
    rescue ex
      logger.warning "Tagger '#{key}' failed: #{ex.message}"
    end

    # Run framework taggers (tech-aware, only instantiated when matching endpoints exist)
    run_framework_taggers(endpoints, options, use_taggers_arr, logger)
  end

  private def self.run_framework_taggers(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers_arr : Array(String), logger : NoirLogger)
    # Group endpoints by technology for efficient dispatch. Indices, not
    # endpoints: Endpoint is a struct, so a tagger that changes a field
    # (`handler = nil`) changes its copy, which is written back below.
    endpoints_by_tech = (0...endpoints.size).to_a.group_by { |idx| endpoints[idx].details.technology }
    endpoints_by_tech.delete(nil)
    return if endpoints_by_tech.empty?

    is_all = use_taggers_arr.includes?("all")

    # Sequentially, in registry order, like the plain taggers: several
    # framework taggers target one tech (`ruby_auth` and `rails_security`
    # both tag Rails endpoints) and append to the same shared tag arrays.
    # They used to run one fiber each, so any blocking read reordered them
    # and an endpoint's tags came out `auth, csrf-protection` on one run and
    # `csrf-protection, auth` on the next. All fibers shared one thread, so
    # the fan-out bought no parallelism.
    FRAMEWORK_ENTRIES.each do |entry|
      # The registry key is the tagger's `name`, so selection is decided
      # before construction — an unselected tagger no longer pays for a
      # logger and a base-path resolution just to be discarded.
      next unless is_all || use_taggers_arr.includes?(entry.key)

      matching_indices = [] of Int32
      target_techs(entry.key).each do |tech|
        if endpoints_by_tech.has_key?(tech)
          matching_indices.concat(endpoints_by_tech[tech])
        end
      end

      next if matching_indices.empty?
      matching_endpoints = matching_indices.map { |idx| endpoints[idx] }

      begin
        build(entry.key, options).try(&.perform(matching_endpoints))
        matching_indices.each_with_index { |idx, pos| endpoints[idx] = matching_endpoints[pos] }
      rescue ex
        logger.warning "Framework tagger '#{entry.key}' failed: #{ex.message}"
      end
    end
  end
end
