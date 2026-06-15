require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect gRPC" do
  options = create_test_options
  instance = Detector::Specification::Grpc.new options

  it "detects a .proto with a service block" do
    content = <<-PROTO
      syntax = "proto3";
      service UserService {
        rpc GetUser(GetUserRequest) returns (GetUserResponse) {}
      }
      PROTO

    instance.detect("user.proto", content).should be_true
  end

  it "detects a service block split across lines" do
    content = <<-PROTO
      syntax = "proto3";
      service HealthService
      {
        rpc Check(Req) returns (Resp);
      }
      PROTO

    instance.detect("health.proto", content).should be_true
  end

  it "rejects a message-only proto whose field names contain 'service'/'rpc'" do
    content = <<-PROTO
      syntax = "proto3";
      message ClientConfig {
        string service_url = 1;
        string service_account = 2;
        int32 rpc_timeout_ms = 3;
        bool enable_rpc_retry = 4;
      }
      PROTO

    instance.detect("config.proto", content).should be_false
  end

  it "rejects a pure message proto" do
    content = <<-PROTO
      syntax = "proto3";
      message Foo {
        string bar = 1;
      }
      PROTO

    instance.detect("types.proto", content).should be_false
  end

  it "applies only to .proto files" do
    instance.applicable?("schema.proto").should be_true
    instance.applicable?("schema.json").should be_false
  end

  it "registers the path in code_locator" do
    content = "service S { rpc M(A) returns (B); }"
    locator = CodeLocator.instance
    locator.clear "grpc-proto"
    instance.detect("svc.proto", content)
    locator.all("grpc-proto").should eq(["svc.proto"])
  end
end
