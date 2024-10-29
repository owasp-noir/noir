require "../../../models/detector"

module Detector::Rust
  class ActixWeb < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("actix-web")
      check = check && file_contents.includes?("dependencies")
      check = check && filename.includes?("Cargo.toml")

      check
    end

    def set_name
      @name = "rust_actix_web"
    end
  end
end
