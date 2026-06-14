require "../../../spec_helper"
require "../../../../src/detector/detectors/cpp/*"

describe "Detect C++ cpp-httplib" do
  options = create_test_options
  instance = Detector::Cpp::Httplib.new options

  it "include <httplib.h>" do
    instance.detect("app.cpp", "#include <httplib.h>").should be_true
  end

  it "include path-prefixed httplib.h" do
    instance.detect("main.cc", "#include <utility/httplib.h>").should be_true
  end

  it "include quoted httplib.hpp" do
    instance.detect("server.hpp", %(#include "httplib/httplib.hpp")).should be_true
  end

  it "httplib::Server reference" do
    instance.detect("main.cxx", "httplib::Server svr;").should be_true
  end

  it "using namespace httplib shorthand" do
    instance.detect("main.cpp", "using namespace httplib;\nServer svr;").should be_true
  end

  it "unrelated cpp file" do
    instance.detect("main.cpp", "#include <iostream>\nint main(){return 0;}").should be_false
  end

  it "non-cpp extension" do
    instance.detect("app.py", "#include <httplib.h>").should be_false
  end
end
