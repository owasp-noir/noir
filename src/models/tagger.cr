require "./logger"

# Marks a `Tagger` (or `FrameworkTagger`) subclass as one entry in the
# tagger registry.
#
#     @[Noir::TaggerFor(key: "hunt", name: "HuntParam Tagger",
#       desc: "Identifies common parameters vulnerable to certain vulnerability classes",
#       order: 10)]
#     class HuntParamTagger < Tagger
#
# `NoirTaggers` reads the registry off the annotated classes, so this line
# is the only place a tagger's `-T` key, its `noir list taggers` name and
# description, and the class that runs it are written down. Before it those
# facts lived in two hand-maintained hash literals; a new tagger file that
# nobody added to them compiled, shipped, and silently never ran.
#
# `key` stays explicit rather than derived from the class name: four of the
# 43 do not follow from it (`hunt` from `HuntParamTagger`, `oauth` from
# `OAuthTagger`, `fastapi_auth` from `FastAPIAuthTagger`,
# `fastendpoints_auth` from `FastEndpointsAuthTagger`). It is also the
# tagger's `name` at runtime — `Tagger#initialize` reads it back off the
# class, so the two can no longer disagree.
#
# `order` fixes the sequence plain taggers run in, which is user-visible:
# they run sequentially, `Endpoint#add_tag` appends, and nothing sorts tags
# before output. Values are spaced by 10 so a tagger can be slotted between
# two others without renumbering. Framework taggers run under a `WaitGroup`,
# so for them it only orders `noir list taggers`.
#
# The `Tagger` and `FrameworkTagger` base classes carry no annotation and
# stay out of the registry — which is also why they can remain instantiable
# for the specs that exercise their default `perform`.
annotation Noir::TaggerFor
end

class Tagger
  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @options = options
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @name = self.class.tagger_key

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  # The registry key, read off the class's `Noir::TaggerFor` annotation.
  # Empty on the un-annotated base classes, which keeps `Tagger.new(...).name`
  # the empty string it has always been.
  #
  # Every concrete tagger used to repeat this as `@name = "hunt"` in its own
  # `initialize` after `super`. `run_tagger` relies on the key and the name
  # being the same string ("selection is decided before construction"); this
  # makes that structural instead of a convention 43 files had to observe.
  def self.tagger_key : String
    {% if ann = @type.annotation(Noir::TaggerFor) %}
      {{ ann[:key] }}
    {% else %}
      ""
    {% end %}
  end

  def name
    @name
  end

  # The per-endpoint shape: look at each endpoint, tag in place, hand the
  # array back. Taggers declare only `check_endpoint`; those that need a
  # pass over the whole set first (a project pre-scan, `mcp`'s legacy
  # prefixes) override `perform` and call `super` or loop themselves.
  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  # Per-endpoint hook for taggers using the inherited `perform`.
  #
  # A no-op rather than `abstract`: the `Tagger` and `FrameworkTagger` bases
  # are instantiated directly by their own specs and by the tagger-registry
  # specs, so they cannot be abstract. A tagger that inherits `perform`
  # without defining this tags nothing — each tagger's unit spec covers it,
  # so that shows up as a failing spec rather than silence.
  protected def check_endpoint(endpoint : Endpoint)
  end

  # Split a URL into lowercased, separator-delimited segments. Shared by the
  # path-keyword taggers. Taggers needing scheme-stripping or other tweaks
  # (e.g. debug) override this locally.
  private def url_parts(url : String) : Array(String)
    url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
  end

  # Canonical parameter-name normalization (lowercase, hyphen -> underscore).
  # Taggers with bespoke normalization (admin's strip-all, pii's camelCase
  # splitter) override this locally.
  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end
end
