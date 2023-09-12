require "../../models/detector"

class DetectorRubyRails < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = file_contents.includes?("gem 'rails'")
    check = check || file_contents.includes?("gem \"rails\"")
    check = check && filename.includes?("Gemfile")

    set_base_path check, get_parent_path(filename)
    check
  end

  def set_name
    @name = "ruby_rails"
  end
end
