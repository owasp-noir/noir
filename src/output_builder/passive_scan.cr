require "../models/output_builder"
require "../models/passive_scan"

require "json"
require "yaml"

class OutputBuilderPassiveScan < OutputBuilder
  def print(passive_results : Array(PassiveScanResult), logger : NoirLogger, is_color : Bool)
    passive_results.each do |result|
      logger.puts "[#{severity_color(result.info.severity, is_color)}][#{result.id.colorize(:light_blue).toggle(is_color)}][#{result.category.colorize(:light_yellow).toggle(is_color)}] #{result.info.name.colorize(:light_green).toggle(is_color)}"
      logger.sub "├── extract: #{result.extract}"
      logger.sub "└── file: #{result.file_path}:#{result.line_number}"
      logger.puts ""
    end
  end

  def severity_color(severity : String, is_color : Bool = true) : String
    case severity
    when "critical"
      severity.colorize(:red).toggle(is_color).to_s
    when "high"
      severity.colorize(:light_red).toggle(is_color).to_s
    when "medium"
      severity.colorize(:yellow).toggle(is_color).to_s
    when "low"
      severity.colorize(:light_yellow).toggle(is_color).to_s
    when "info"
      severity.colorize(:light_blue).toggle(is_color).to_s
    else
      severity.colorize(:white).toggle(is_color).to_s
    end
  end
end
