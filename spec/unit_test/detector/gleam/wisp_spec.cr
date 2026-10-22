require "../../../spec_helper"
require "../../../../src/detector/detectors/gleam/*"

describe "Detect Gleam Wisp" do
  options = create_test_options
  instance = Detector::Gleam::Wisp.new options

  it "detects wisp in gleam.toml dependencies" do
    manifest = <<-TOML
      name = "my_app"
      version = "1.0.0"

      [dependencies]
      gleam_stdlib = ">= 0.49.0 and < 2.0.0"
      wisp = ">= 1.4.0 and < 2.0.0"
      TOML

    instance.detect("gleam.toml", manifest).should be_true
  end

  # Vendored / monorepo checkouts use a path dependency, so the import is
  # the only signal.
  it "detects a wisp import in a .gleam file" do
    router = <<-GLEAM
      import wisp.{type Request, type Response}

      pub fn handle_request(req: Request) -> Response {
        case wisp.path_segments(req) {
          [] -> wisp.ok()
          _ -> wisp.not_found()
        }
      }
      GLEAM

    instance.detect("src/app/router.gleam", router).should be_true
  end

  it "does not detect Gleam files that never touch wisp" do
    plain = <<-GLEAM
      import gleam/io

      pub fn main() {
        io.println("Hello, Joe!")
      }
      GLEAM

    instance.detect("src/main.gleam", plain).should be_false
  end

  it "does not detect a gleam.toml without wisp" do
    manifest = <<-TOML
      name = "my_app"

      [dependencies]
      gleam_stdlib = ">= 0.49.0 and < 2.0.0"
      TOML

    instance.detect("gleam.toml", manifest).should be_false
  end
end
