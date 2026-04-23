require "../../../models/detector"

module Detector::Ruby
  class Roda < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return true if file_contents.includes?("gem 'roda'")
        return true if file_contents.includes?("gem \"roda\"")
      end

      if filename.ends_with?(".rb")
        return true if file_contents =~ /<\s*Roda\b/
        return true if file_contents.includes?("Roda.route")
        return true if file_contents =~ /require\s+['"]roda['"]/
      end

      false
    end

    def set_name
      @name = "ruby_roda"
    end
  end
end
