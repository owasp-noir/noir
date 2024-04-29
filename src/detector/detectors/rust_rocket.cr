require "../../models/detector"

class DetectorRustRocket < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = file_contents.includes?("rocket")
    check = check && file_contents.includes?("dependencies")
    check = check && filename.includes?("Cargo.toml")

    check
  end

  def set_name
    @name = "rust_rocket"
  end
end
