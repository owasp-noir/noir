require "../../../spec_helper"
require "../../../../src/detector/detectors/cpp/*"

describe "Detect C++ Drogon" do
  options = create_test_options
  instance = Detector::Cpp::Drogon.new options

  it "main.cpp with drogon include" do
    instance.detect("main.cpp", %(#include <drogon/drogon.h>\nint main() { app().run(); })).should be_true
  end

  it "UsersController.h with HttpController include" do
    instance.detect("UsersController.h", %(#include "drogon/HttpController.h")).should be_true
  end

  it "registerHandler call without include" do
    instance.detect("routes.cc", %(app().registerHandler("/ping", handler, {Get});)).should be_true
  end

  it "PATH_LIST_BEGIN macro" do
    instance.detect("controller.cpp", "PATH_LIST_BEGIN\nPATH_ADD(\"/x\", Get);\nPATH_LIST_END").should be_true
  end

  it "CMakeLists.txt with find_package(Drogon)" do
    instance.detect("CMakeLists.txt", "find_package(Drogon CONFIG REQUIRED)").should be_true
  end

  it "non-drogon source" do
    instance.detect("main.cpp", %(#include <iostream>\nint main() { return 0; })).should be_false
  end
end
