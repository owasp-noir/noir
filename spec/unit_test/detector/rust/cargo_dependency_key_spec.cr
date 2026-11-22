require "../../../spec_helper"
require "../../../../src/detector/detector"

# A framework name inside a comment (qdrant's `lib/edge/ffi/Cargo.toml` says
# "the gRPC/router stack (tonic/axum) is trimmed") or a sibling crate must not
# fire the analyzer: with no manifest depending on the crate, the analyzer's
# crate-root gate waves every `.rs` file through and parses them all.
describe "Rust detectors read the Cargo dependency key" do
  registry = build_detector_list(create_test_options).index_by(&.name)

  {
    {registry["rust_axum"], "axum"},
    {registry["rust_actix_web"], "actix-web"},
    {registry["rust_rocket"], "rocket"},
    {registry["rust_warp"], "warp"},
    {registry["rust_salvo"], "salvo"},
    {registry["rust_tide"], "tide"},
    {registry["rust_gotham"], "gotham"},
    {registry["rust_loco"], "loco-rs"},
    {registry["rust_rwf"], "rwf"},
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
