require "./taggers/*"
require "./framework_taggers/**"
require "../models/tagger"
require "../models/framework_tagger"
require "wait_group"

module NoirTaggers
  # One tagger, as declared by its class's `Noir::TaggerFor` annotation.
  #
  # `runner` is deliberately not a field. Storing the class object erases
  # `self.target_techs` — it lives on `FrameworkTagger`, not on `Tagger` —
  # so every read would need a cast back. The two macro-generated `case`
  # dispatchers below resolve per concrete class instead, the same shape
  # `Noir::OutputFormats.render` uses.
  record Entry, key : String, name : String, desc : String, framework : Bool

  # Every annotated tagger, in `order`. Derived from the classes, so a
  # tagger joins the registry by existing: the two hand-maintained hash
  # literals this replaces were a second place to remember, where
  # forgetting produced no error and no failing spec — just a tagger that
  # never ran.
  ENTRIES = begin
    {% begin %}
      [
        {% for tagger in Tagger.all_subclasses
                           .select(&.annotation(Noir::TaggerFor))
                           .sort_by { |sub| sub.annotation(Noir::TaggerFor)[:order] } %}
          {% ann = tagger.annotation(Noir::TaggerFor) %}
          Entry.new({{ ann[:key] }}, {{ ann[:name] }}, {{ ann[:desc] }},
            {{ tagger.ancestors.includes?(FrameworkTagger) }}),
        {% end %}
      ] of Entry
    {% end %}
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
        nil
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

  def self.unknown_tagger_names(use_taggers : String) : Array(String)
    requested = use_taggers.split(",").map(&.strip).reject(&.empty?)
    valid_names = available_tagger_names
    # Case-insensitive match: canonical names in `valid_names` are
    # lowercase. `--use-taggers Hunt` and `--use-taggers HUNT` were
    # rejected pre-fix even though the user clearly intended `hunt`;
    # `noir list taggers` doesn't communicate that the names are
    # case-sensitive either.
    requested.reject { |name| valid_names.includes?(name.downcase) }
  end

  def self.validate_tagger_names!(use_taggers : String)
    unknown = unknown_tagger_names(use_taggers)
    return if unknown.empty?

    raise ArgumentError.new("Unknown tagger(s): #{unknown.join(", ")}")
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers : String)
    validate_tagger_names!(use_taggers)

    # Parsing use_taggers — normalize to lowercase so case-insensitive
    # input matches the lowercase canonical tagger names. Validation
    # (`validate_tagger_names!` above) uses the same shape.
    use_taggers_arr = use_taggers.split(",").map(&.strip.downcase)
    is_all = use_taggers_arr.includes?("all")

    logger = NoirLogger.from_options(options)

    with_route_paths(endpoints, options["url"]?.to_s) do
      run_selected(endpoints, options, use_taggers_arr, is_all, logger)
    end
  end

  # The optimizer has already joined `-u` onto every endpoint URL by the time
  # taggers run, but taggers match route text: tokenised path words, Ant
  # patterns, group prefixes. Fed `http://admin.example.com/a` they tagged
  # every endpoint `admin`, and a `/api/public/**` permitAll rule stopped
  # matching. Show them the route path for the pass, then put the URL back.
  private def self.with_route_paths(endpoints : Array(Endpoint), target : String, &)
    return yield if target.empty?

    originals = endpoints.map(&.url)
    endpoints.each_with_index do |endpoint, idx|
      next unless endpoint.url.starts_with?(target)
      rest = endpoint.url[target.size..]
      # `combine_url_and_endpoints` leaves `/` at the seam unless the target
      # ends in one, so anything else is an absolute URL whose host merely
      # starts with the target's text (`http://h` vs `http://host2/x`).
      next unless rest.empty? || rest.starts_with?('/') || target.ends_with?('/')
      endpoint.url = rest.starts_with?('/') ? rest : "/#{rest}"
      endpoints[idx] = endpoint
    end

    begin
      yield
    ensure
      endpoints.each_with_index do |endpoint, idx|
        endpoint.url = originals[idx]
        endpoints[idx] = endpoint
      end
    end
  end

  private def self.run_selected(endpoints : Array(Endpoint), options : Hash(String, YAML::Any),
                                use_taggers_arr : Array(String), is_all : Bool, logger : NoirLogger)
    # The registry key IS the tagger's `name` (`Tagger#initialize` reads it
    # back off the class), so an unselected tagger can be skipped without
    # constructing it — each `new` builds a logger and resolves options. Run
    # the selected ones in registry order, which is user-visible: tags are
    # appended in the order taggers run and nothing sorts them before
    # output. A single tagger raising must not abort the rest of the pass
    # (or, for framework taggers below, tear down the whole program from
    # inside a fiber) — degrade to "this tagger failed".
    PLAIN_ENTRIES.each do |entry|
      next unless is_all || use_taggers_arr.includes?(entry.key)
      begin
        build(entry.key, options).try(&.perform(endpoints))
      rescue ex
        logger.warning "Tagger '#{entry.key}' failed: #{ex.message}"
      end
    end

    # Run framework taggers (tech-aware, only instantiated when matching endpoints exist)
    run_framework_taggers(endpoints, options, use_taggers_arr, logger)
  end

  private def self.run_framework_taggers(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers_arr : Array(String), logger : NoirLogger)
    # Group endpoints by technology for efficient dispatch
    endpoints_by_tech = endpoints.group_by(&.details.technology)
    endpoints_by_tech.delete(nil)
    return if endpoints_by_tech.empty?

    is_all = use_taggers_arr.includes?("all")

    # Collect tagger work items, then run in parallel
    WaitGroup.wait do |wg|
      FRAMEWORK_ENTRIES.each do |entry|
        # The registry key is the tagger's `name`, so selection is decided
        # before construction — an unselected tagger no longer pays for a
        # logger and a base-path resolution just to be discarded.
        next unless is_all || use_taggers_arr.includes?(entry.key)

        matching_endpoints = [] of Endpoint
        target_techs(entry.key).each do |tech|
          if endpoints_by_tech.has_key?(tech)
            matching_endpoints.concat(endpoints_by_tech[tech])
          end
        end

        next if matching_endpoints.empty?

        # Bind to local variables to ensure each fiber captures its own copy
        local_instance = build(entry.key, options)
        next if local_instance.nil?
        local_endpoints = matching_endpoints

        wg.spawn do
          local_instance.perform(local_endpoints)
        rescue ex
          logger.warning "Framework tagger '#{local_instance.name}' failed: #{ex.message}"
        end
      end
    end
  end
end
