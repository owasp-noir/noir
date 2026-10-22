require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/grpc"

private def analyze_proto(content : String)
  path = File.tempname("grpc", ".proto")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear Noir::LocatorKeys::GRPC_PROTO
  locator.push Noir::LocatorKeys::GRPC_PROTO, path

  Analyzer::Specification::Grpc.new(create_test_options).analyze
ensure
  CodeLocator.instance.clear Noir::LocatorKeys::GRPC_PROTO
  File.delete(path) if path && File.exists?(path)
end

describe "gRPC Analyzer" do
  it "reports each service's own line for same-named rpcs" do
    endpoints = analyze_proto <<-PROTO
      syntax = "proto3";
      package admin.v1;

      service UserService {
        rpc Get(GetRequest) returns (Entity);
        rpc List(ListRequest) returns (ListResponse);
      }

      service GroupService {
        // rpc Get(Old) returns (Old);
        rpc Get(GetRequest) returns (Entity);
        rpc List(ListRequest) returns (ListResponse);
      }
      PROTO

    endpoints.map { |e| {e.url, e.details.code_paths[0].line} }.should eq([
      {"/admin.v1.UserService/Get", 5},
      {"/admin.v1.UserService/List", 6},
      {"/admin.v1.GroupService/Get", 11},
      {"/admin.v1.GroupService/List", 12},
    ])
  end
end
