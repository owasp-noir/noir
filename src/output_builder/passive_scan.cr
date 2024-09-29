require "../models/output_builder"
require "../models/passive_scan"

require "json"
require "yaml"

class OutputBuilderPassiveScan < OutputBuilder
    def print(passive_results : Array(PassiveScanResult))
        passive_results.each do |result|
            puts "ID: #{result.id}"
            puts "Info: #{result.info}"
            puts "Matchers: #{result.matchers}"
            puts "Matchers Condition: #{result.matchers_condition}"
            puts "Category: #{result.category}"
            puts "Techs: #{result.techs.join(", ")}"
            puts "File Path: #{result.file_path}"
            puts "Line Number: #{result.line_number}"
            puts "Extract: #{result.extract}"
            puts "-" * 40
          end
    end
end