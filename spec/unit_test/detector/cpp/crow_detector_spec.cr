require "../../../spec_helper"
require "../../../../src/detector/detectors/cpp/*"

describe "Detect C++ Crow" do
  options = create_test_options
  instance = Detector::Cpp::Crow.new options

  it "include crow.h quoted" do
    instance.detect("app.cpp", %(#include "crow.h")).should be_true
  end

  it "include <crow.h>" do
    instance.detect("app.cpp", "#include <crow.h>").should be_true
  end

  it "include <crow/app.h>" do
    instance.detect("server.cc", "#include <crow/app.h>").should be_true
  end

  it "CROW_ROUTE macro" do
    instance.detect("main.cxx", "CROW_ROUTE(app, \"/\")([](){ return \"ok\"; });").should be_true
  end

  it "crow::SimpleApp reference" do
    instance.detect("main.hpp", "crow::SimpleApp app;").should be_true
  end

  it "unrelated cpp file" do
    instance.detect("main.cpp", "#include <iostream>\nint main(){return 0;}").should be_false
  end

  it "non-cpp extension" do
    instance.detect("app.py", %(#include "crow.h")).should be_false
  end
end
