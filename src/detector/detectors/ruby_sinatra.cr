require "../../models/detector"

class DetectorRubySinatra < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = file_contents.includes?("gem 'sinatra'")
    check = check || file_contents.includes?("gem \"sinatra\"")
    check = check && filename.includes?("Gemfile")

    set_base_path check, get_parent_path(filename)
    check
  end

  def set_name
    @name = "ruby_sinatra"
  end
end
