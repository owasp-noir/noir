require "../../../spec_helper"
require "../../../../src/detector/detectors/c/*"

describe "Detect C Mongoose" do
  options = create_test_options
  instance = Detector::C::Mongoose.new options

  it "includes mongoose.h" do
    instance.detect("main.c", %(#include "mongoose.h")).should be_true
  end

  it "includes mongoose.h from C++" do
    instance.detect("main.cpp", "#include <mongoose.h>").should be_true
  end

  it "plain C file" do
    instance.detect("main.c", "#include <stdio.h>\nint main(void){return 0;}").should be_false
  end
end
