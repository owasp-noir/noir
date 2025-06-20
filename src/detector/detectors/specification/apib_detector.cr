require "../../../models/detector"
require "../../../models/logger" # Assuming logger is needed

module Detector
  module Specification
    class ApiBlueprint < Detector::Base
      APIB_SPEC_TYPE = "apib" # This will be the 'name' of the detector

      def initialize(options : Hash(String, YAML::Any))
        super(options)
        @name = APIB_SPEC_TYPE
      end

      # This method will be called by the main loop in src/detector/detector.cr
      def detect(file_path : String, content : String) : Bool
        filename = Path.new(file_path).filename
        extension = Path.new(file_path).extension.downcase

        # 1. Check for .apib extension
        if extension == ".apib"
          logger.debug "Detected APIB by extension: #{file_path}"
          return true
        end

        # 2. Check .md files for API Blueprint content
        if extension == ".md"
          begin
            # Content is already passed in, use the first few lines for sniffing
            # Split content into lines and take up to 20
            content_sample_lines = content.lines.first(20)
            content_sample = content_sample_lines.join("\n")

            if content_sample.includes?("FORMAT: 1A") ||
               content_sample.match(/^#+\s*Group\s+.*$/) ||
               content_sample.match(/^#+\s*.*\[\s*\/.*\s*\].*$/) # Matches "## Resource [/path]"
              logger.debug "Detected APIB by content in .md file: #{file_path}"
              return true
            end
          rescue ex
            logger.warn "Error processing .md file for APIB content detection: #{file_path} - #{ex.message}"
          end
        end

        false
      end
    end
  end
end
