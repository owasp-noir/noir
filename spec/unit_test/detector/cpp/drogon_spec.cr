require "../../../spec_helper"
require "../../../../src/detector/detector"

# Direct detection also recognizes this file outside the scanner dispatch gate.
describe "cpp_drogon direct detection" do
  instance = build_detector_list(create_test_options).find! { |detector| detector.name == "cpp_drogon" }

  it "CMakeLists.txt with find_package(Drogon)" do
    instance.detect("CMakeLists.txt", "find_package(Drogon CONFIG REQUIRED)").should be_true
  end
end
