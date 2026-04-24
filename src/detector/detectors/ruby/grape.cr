require "../../../models/detector"

module Detector::Ruby
  class Grape < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return true if file_contents.includes?("gem 'grape'")
        return true if file_contents.includes?("gem \"grape\"")
      end

      if filename.ends_with?(".rb")
        return true if file_contents.includes?("Grape::API")
        return true if file_contents.includes?("< Grape::API")
        return true if file_contents.matches?(/require\s+['"]grape['"]/)
      end

      false
    end

    def set_name
      @name = "ruby_grape"
    end
  end
end
