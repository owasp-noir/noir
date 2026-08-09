require "../models/output_builder"
require "./adb"
require "./common"
require "./curl"
require "./html"
require "./httpie"
require "./json"
require "./jsonl"
require "./markdown_table"
require "./mermaid"
require "./oas2"
require "./oas3"
require "./only-cookie"
require "./only-header"
require "./only-param"
require "./only-tag"
require "./only-url"
require "./postman"
require "./powershell"
require "./sarif"
require "./simctl"
require "./toml"
require "./yaml"

# The catalog of `-f/--format` values, derived from the `Noir::OutputFormat`
# annotation each builder carries.
#
# Everything that needs to know which formats exist reads it from here: the
# scan's report dispatch, `--format` validation, the `-f` help text, `noir
# list formats`, and the four shell completion generators. A format joins all
# of them by annotating its builder class — the annotation is the only place
# its name, description and renderer are written down.
module Noir::OutputFormats
  record Entry, name : String, description : String

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
          Entry.new({{ format[:name] }}, {{ format[:description] }}),
        {% end %}
      ] of Entry
    {% end %}
  end

  NAMES = ENTRIES.map(&.name)

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
  def self.render(format : String,
                  options : Hash(String, YAML::Any),
                  endpoints : Array(Endpoint),
                  passive_results : Array(PassiveScanResult)) : Bool
    {% begin %}
      case format
      {% for builder in OutputBuilder.all_subclasses.select(&.annotation(Noir::OutputFormat)) %}
      when {{ builder.annotation(Noir::OutputFormat)[:name] }}
        {{ builder }}.new(options).print(endpoints, passive_results)
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
