require "../detector"

module Detector
  module Python
    class Robyn < Detector::Detector
      def initialize
        super
        set_name("python_robyn")
        set_version("0.0.1")
      end

      # Detects if the file contents use the Robyn framework.
      #
      # Args:
      #   file_contents: The content of the file to check.
      #
      # Returns:
      #   True if the file contents indicate usage of Robyn, false otherwise.
      def detect(file_contents : String) : Bool
        return file_contents.includes?("from robyn import Robyn") || file_contents.includes?("import robyn")
      end
    end
  end
end
