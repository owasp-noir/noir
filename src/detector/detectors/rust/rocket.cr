require "../../../models/detector"

module Detector::Rust
  class Rocket < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = filename.includes?("Cargo.toml")
      check = check && file_contents.includes?("rocket")
      check = check && file_contents.includes?("dependencies")

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rs") || File.basename(filename) == "Cargo.toml" || File.basename(filename) == "Cargo.lock"
    end

    def set_name
      @name = "rust_rocket"
    end
  end
end
