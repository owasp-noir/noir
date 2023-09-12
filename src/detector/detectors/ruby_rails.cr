require "../../models/detector"

class DetectorRubyRails < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = file_contents.includes?("gem 'rails'")
    check = check || file_contents.includes?("gem \"rails\"")
    check = check && filename.includes?("Gemfile")

    check
  end

  def set_name
    @name = "ruby_rails"
  end
end
