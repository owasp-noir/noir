require "../../../models/detector"

module Detector::Ruby
  class Sinatra < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Gemfile")

      check = file_contents.includes?("gem 'sinatra'")
      check = check || file_contents.includes?("gem \"sinatra\"")

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") || filename.ends_with?(".ru") || File.basename(filename) == "Gemfile" || File.basename(filename) == "Gemfile.lock"
    end

    def set_name
      @name = "ruby_sinatra"
    end
  end
end
