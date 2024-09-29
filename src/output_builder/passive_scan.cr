require "../models/output_builder"
require "../models/passive_scan"

require "json"
require "yaml"

class OutputBuilderPassiveScan < OutputBuilder
  def print(passive_results : Array(PassiveScanResult), logger : NoirLogger, is_color : Bool)
    passive_results.each do |result|
      logger.puts "[#{result.id.colorize(:light_blue).toggle(is_color)}][#{result.category.colorize(:light_yellow).toggle(is_color)}] #{result.info.name.colorize(:light_green).toggle(is_color)}"
      logger.sub "├── extract: #{result.extract}"
      logger.sub "└── file: #{result.file_path}:#{result.line_number}"
    end
  end
end
