require "../../../spec_helper"
require "../../../../src/detector/detectors/cpp/*"

describe "Detect C++ oat++" do
  options = create_test_options
  instance = Detector::Cpp::Oatpp.new options

  it "ApiController base class" do
    instance.detect("UserController.hpp", "class C : public oatpp::web::server::api::ApiController {").should be_true
  end

  it "OATPP_CODEGEN_BEGIN(ApiController) marker" do
    instance.detect("Controller.hpp", "#include OATPP_CODEGEN_BEGIN(ApiController)").should be_true
  end

  it "oatpp include" do
    instance.detect("main.cpp", %(#include "oatpp/web/server/HttpConnectionHandler.hpp")).should be_true
  end

  it "unrelated cpp file" do
    instance.detect("main.cpp", "#include <iostream>\nint main(){return 0;}").should be_false
  end

  it "non-cpp extension" do
    instance.detect("app.py", "oatpp::web::server::api::ApiController").should be_false
  end
end
