require "../models/output_builder"
require "../models/passive_scan"

require "json"
require "yaml"

class OutputBuilderPassiveScan < OutputBuilder
  # Findings go out through `ob_puts`, like every other builder's report
  # content, rather than straight to the logger. Three things follow from
  # that, and none of them held before:
  #   * `-o` finally receives the findings. `noir scan . -P -o report.txt`
  #     wrote the endpoint list to the file and left the secrets on stdout
  #     only, so the saved report was missing the part `-P` was run for.
  #   * The file copy is plain text, and so is a redirected stdout. The
  #     `is_color` this used to be handed came from `NoirRunner`, which
  #     reads the `color` option with no terminal check because that same
  #     flag also colors stderr progress logs; `@is_color` here is the
  #     TTY-aware one, so `-P > findings.txt` no longer gets ANSI codes.
  #   * A closed downstream pipe (`| head`) stops the stdout writes but lets
  #     the `-o` file finish, instead of `exit(0)`-ing mid-report.
  def print(passive_results : Array(PassiveScanResult))
    passive_results.each do |result|
      severity = severity_color(result.info.severity)
      id = result.id.colorize(:light_blue).toggle(@is_color)
      category = result.category.colorize(:light_yellow).toggle(@is_color)
      name = result.info.name.colorize(:light_green).toggle(@is_color)

      ob_puts "[#{severity}][#{id}][#{category}] #{name}"
      # Indented to match `NoirLogger#puts_sub`. These two lines are part of
      # the finding — the extract, and the file:line that says where the
      # secret is — not progress logging, so they share the report stream.
      ob_puts "  ├── extract: #{result.extract}"
      ob_puts "  └── file: #{result.file_path}:#{result.line_number}"
      ob_puts ""
    end
  end

  def severity_color(severity : String) : String
    case severity
    when "critical"
      severity.colorize(:red).toggle(@is_color).to_s
    when "high"
      severity.colorize(:light_red).toggle(@is_color).to_s
    when "medium"
      severity.colorize(:yellow).toggle(@is_color).to_s
    when "low"
      severity.colorize(:light_yellow).toggle(@is_color).to_s
    when "info"
      severity.colorize(:light_blue).toggle(@is_color).to_s
    else
      severity.colorize(:white).toggle(@is_color).to_s
    end
  end
end
