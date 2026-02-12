require "../../../models/detector"

module Detector::Ruby
  class Rails < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Gemfile")

      check = file_contents.includes?("gem 'rails'")
      check = check || file_contents.includes?("gem \"rails\"")

      check
    end

    def set_name
      @name = "ruby_rails"
    end
  end
end
