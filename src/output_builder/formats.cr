require "../models/output_builder"
# Glob rather than a per-format line. This was the last explicit require list
# in the repo that grew with every contribution — one guaranteed one-line
# merge conflict per new output format, in a file whose whole purpose is that
# a format registers itself.
#
# Requiring this file from inside the directory it globs is fine: Crystal
# tracks what it has already required, so the self-reference is a no-op.
#
# The glob also picks up the five non-format files here (`diff`,
# `mobile_launch`, `passive_scan`, `oas_common`, `toml_serializer`). They carry
# no `Noir::OutputFormat` annotation, so they cannot reach `ENTRIES`, and
# `src/models/noir.cr` already loads all of them via `require
# "../output_builder/*"` — the explicit list only ever existed so this file
# could also be required standalone (from `src/options.cr`).
require "./*"

# The catalog of `-f/--format` values, derived from the `Noir::OutputFormat`
# annotation each builder carries.
#
# Everything that needs to know which formats exist reads it from here: the
# scan's report dispatch, `--format` validation, the `-f` help text, `noir
# list formats`, and the four shell completion generators. A format joins all
# of them by annotating its builder class — the annotation is the only place
# its name, description and renderer are written down.
module Noir::OutputFormats
  record Entry, name : String, description : String, structured : Bool

  # Ordered by the annotation's `order:`, so help output and `noir list
  # formats` group related formats (structured → command → spec → only-* →
  # diagram) instead of following `require` order.
  ENTRIES = begin
    {% begin %}
      [
        {% for builder in OutputBuilder.all_subclasses
                            .select(&.annotation(Noir::OutputFormat))
                            .sort_by { |sub| sub.annotation(Noir::OutputFormat)[:order] } %}
          {% format = builder.annotation(Noir::OutputFormat) %}
          Entry.new({{ format[:name] }}, {{ format[:description] }}, {{ !!format[:structured] }}),
        {% end %}
      ] of Entry
    {% end %}
  end

  NAMES = ENTRIES.map(&.name)

  # Formats whose output is a document with an envelope, so "no endpoints" must
  # still render — `{"endpoints":[],"passive_results":[]}`, a `"paths": {}` OAS
  # document, a header-only Markdown table, a full HTML shell. Downstream
  # consumers (jq pipelines, Postman importers, CI report uploaders) treat empty
  # or missing output as a hard error.
  #
  # Command-list and line-list formats (curl, httpie, powershell, adb, simctl,
  # only-*) and `plain` are deliberately *not* structured: they have no
  # envelope, so emitting nothing is their correct empty output.
  #
  # Declared on the builder as `structured: true`. This used to be a
  # hand-maintained `Set` in `src/cli/commands/scan.cr` — a subset of a derived
  # list, which is the shape that silently rots: a new structured format that
  # nobody remembered to add there emitted *nothing at all* on a zero-endpoint
  # scan, with no error and no failing spec.
  STRUCTURED_NAMES = ENTRIES.select(&.structured).map(&.name).to_set

  # Whether `name` must still be rendered when a scan found no endpoints.
  def self.structured?(name : String) : Bool
    STRUCTURED_NAMES.includes?(name)
  end

  # The format used when `-f` is absent, and the fallback for a value that
  # reached the runner without passing validation (library callers construct
  # the options hash directly).
  DEFAULT = "plain"

  def self.known?(name : String) : Bool
    NAMES.includes?(name)
  end

  # Renders the report in `format`, returning false when no builder claims
  # that name so the caller can fall back to `DEFAULT`.
  #
  # Each `when` branch instantiates one concrete builder, so the call is
  # resolved per class rather than through the `OutputBuilder` base type —
  # which is what lets builders keep their own `print` overloads.
  #
  # `errors` reaches the builder as a property rather than a `print`
  # argument, so the formats with nowhere to put it (every command and
  # only-* format) need no signature change. It defaults to empty for
  # callers that render a report they did not scan for.
  def self.render(format : String,
                  options : Hash(String, YAML::Any),
                  endpoints : Array(Endpoint),
                  passive_results : Array(PassiveScanResult),
                  errors : Array(AnalyzerFailure) = [] of AnalyzerFailure) : Bool
    {% begin %}
      case format
      {% for builder in OutputBuilder.all_subclasses.select(&.annotation(Noir::OutputFormat)) %}
      when {{ builder.annotation(Noir::OutputFormat)[:name] }}
        # Named `renderer`, not `builder`: `builder` is the macro loop
        # variable holding the class, and reusing it for the instance makes
        # the two impossible to tell apart when reading the expansion.
        renderer = {{ builder }}.new(options)
        renderer.analyzer_failures = errors
        renderer.print(endpoints, passive_results)
      {% end %}
      else
        return false
      end
    {% end %}
    true
  end

  # `-f` help block for the CLI option parser, indented to sit under the
  # flag's description.
  def self.help_text(indent : String = "  ") : String
    width = ENTRIES.max_of(&.name.size) + 2
    ENTRIES.map { |entry| "#{indent}#{entry.name.ljust(width)} #{entry.description}" }.join("\n")
  end
end
