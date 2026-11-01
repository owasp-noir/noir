require "../../../spec_helper"
require "../../../../src/detector/detectors/rust/*"

# A framework name inside a comment (qdrant's `lib/edge/ffi/Cargo.toml` says
# "the gRPC/router stack (tonic/axum) is trimmed") or a sibling crate must not
# fire the analyzer: with no manifest depending on the crate, the analyzer's
# crate-root gate waves every `.rs` file through and parses them all.
describe "Rust detectors read the Cargo dependency key" do
  options = create_test_options

  {
    {Detector::Rust::Axum.new(options), "axum"},
    {Detector::Rust::ActixWeb.new(options), "actix-web"},
    {Detector::Rust::Rocket.new(options), "rocket"},
    {Detector::Rust::Warp.new(options), "warp"},
    {Detector::Rust::Salvo.new(options), "salvo"},
    {Detector::Rust::Tide.new(options), "tide"},
    {Detector::Rust::Gotham.new(options), "gotham"},
    {Detector::Rust::Loco.new(options), "loco-rs"},
    {Detector::Rust::Rwf.new(options), "rwf"},
  }.each do |instance, crate|
    it "#{crate}: key, dotted key and table form count" do
      instance.detect("Cargo.toml", "[dependencies]\n#{crate} = \"1\"").should be_true
      instance.detect("Cargo.toml", "[workspace.dependencies]\n#{crate}.workspace = true").should be_true
      instance.detect("Cargo.toml", "[dependencies.#{crate}]\nversion = \"1\"").should be_true
    end

    it "#{crate}: renamed, quoted-key and target-table forms count (detect loose, gate strict)" do
      instance.detect("Cargo.toml", "[dependencies]\nweb = { package = \"#{crate}\", version = \"1\" }").should be_true
      instance.detect("Cargo.toml", "[dependencies]\n\"#{crate}\" = \"1\"").should be_true
      instance.detect("Cargo.toml", "[target.'cfg(unix)'.dependencies.#{crate}]\nversion = \"1\"").should be_true
      instance.detect("Cargo.toml", "[dependencies]\n# web = { package = \"#{crate}\" }").should be_false
    end

    it "#{crate}: comment, string and sibling crate do not count" do
      instance.detect("Cargo.toml", "[dependencies]\n# trimmed with #{crate} off\nserde = \"1\"").should be_false
      instance.detect("Cargo.toml", "[dependencies]\ndescription = \"uses #{crate}\"").should be_false
      instance.detect("Cargo.toml", "[dependencies]\n#{crate}-extra = \"1\"").should be_false
    end
  end
end
