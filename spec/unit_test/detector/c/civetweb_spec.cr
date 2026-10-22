require "../../../spec_helper"
require "../../../../src/detector/detectors/c/*"

describe "Detect C CivetWeb" do
  options = create_test_options
  instance = Detector::C::Civetweb.new options

  it "includes civetweb.h" do
    instance.detect("server.c", %(#include "civetweb.h")).should be_true
  end

  it "includes the C++ wrapper header" do
    instance.detect("server.cpp", %(#include "CivetServer.h")).should be_true
  end

  it "plain C file" do
    instance.detect("server.c", "#include <string.h>").should be_false
  end
end
