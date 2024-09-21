require "../../../models/detector"

module Detector::Ruby
  class Hanami < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("gem 'hanami'")
      check = check || file_contents.includes?("gem \"hanami\"")
      check = check && filename.includes?("Gemfile")

      check
    end

    def set_name
      @name = "ruby_hanami"
    end
  end
end
