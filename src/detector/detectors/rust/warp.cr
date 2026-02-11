require "../../../models/detector"

module Detector::Rust
  class Warp < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Cargo.toml")

      check = file_contents.includes?("warp")
      check = check && file_contents.includes?("dependencies")

      check
    end

    def set_name
      @name = "rust_warp"
    end
  end
end
