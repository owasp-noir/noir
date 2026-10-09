require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Thrift" do
  options = create_test_options
  instance = Detector::Specification::Thrift.new options

  it "detects a .thrift with a service block" do
    content = <<-THRIFT
      namespace java com.ex
      service UserService {
        User getUser(1: i64 id)
      }
      THRIFT

    instance.detect("user.thrift", content).should be_true
  end

  it "detects a service that extends an included base, split across lines" do
    content = <<-THRIFT
      include "shared.thrift"
      service Calculator
        extends shared.SharedService
      {
        i32 add(1: i32 a, 2: i32 b)
      }
      THRIFT

    instance.detect("calc.thrift", content).should be_true
  end

  it "rejects a struct-only IDL whose fields are named service/rpc" do
    content = <<-THRIFT
      struct ClientConfig {
        1: string service
        2: i32 rpc_timeout_ms
      }
      THRIFT

    instance.detect("config.thrift", content).should be_false
  end

  it "rejects a service block that only appears in comments" do
    content = <<-THRIFT
      # service Old { void a() }
      // service Older { void b() }
      /* service Oldest {
           void c()
         } */
      struct Keep { 1: i32 x }
      THRIFT

    instance.detect("legacy.thrift", content).should be_false
  end

  it "applies only to .thrift files" do
    instance.applicable?("api.thrift").should be_true
    instance.applicable?("api.proto").should be_false
    instance.applicable?("service.txt").should be_false
  end

  it "registers the path in code_locator" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::THRIFT_IDL
    instance.detect("svc.thrift", "service S { void m() }")
    locator.all(Noir::LocatorKeys::THRIFT_IDL).should eq(["svc.thrift"])
  end
end
