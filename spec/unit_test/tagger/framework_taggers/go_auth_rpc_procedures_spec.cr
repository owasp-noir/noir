require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

# gRPC / Connect endpoints: an interceptor that lets anonymous callers
# through by procedure name (see `GoRpcProcedureGate`).
private def rpc_guards(base : String, url : String, tech : String = "go_connect_rpc", file : String = "server.go", line : Int32 = 1) : Array(String)
  CodeLocator.instance.clear_all
  Dir.glob("#{base}/**/*.go").each { |f| CodeLocator.instance.register_path(f) }
  options = create_test_options
  options["base"] = YAML::Any.new(base)
  details = Details.new(PathInfo.new("#{base}/#{file}", line))
  details.technology = tech
  endpoint = Endpoint.new(url, "POST", [] of Param, details)
  GoAuthTagger.new(options).perform([endpoint]).first.tags.select(&.name.in?("auth", "authz")).map(&.name)
end

private def with_go_tree(files : Hash(String, String), &)
  dir = File.tempname("rpc_procedures")
  files.each do |name, body|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
  end
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "GoAuthTagger (RPC procedure allow-lists)" do
  base = File.expand_path("../../../functional_test/fixtures/go/connect_rpc_public_procedures", __DIR__)

  it "guards every procedure of the package the allow-list does not name" do
    rpc_guards(base, "/notes.api.AuthService/GetCurrentUser", file: "server/api/server.go", line: 27).should eq(["auth"])
    rpc_guards(base, "/notes.api.NoteService/DeleteNote", file: "server/api/server.go", line: 28).should eq(["auth"])
    rpc_guards(base, "/notes.api.AuthService/SignIn", file: "server/api/server.go", line: 27).should be_empty
  end

  it "does not read a narrower list checked after the gate as a gate of its own" do
    # `if IsBootstrapMethod(p) { return nil }` follows `!IsPublicMethod(p)`;
    # the refusal after it is the private-instance setting's.
    rpc_guards(base, "/notes.api.NoteService/ListNotes", file: "server/api/server.go", line: 28).should be_empty
  end

  it "maps a gateway route back to its procedure through the proto file" do
    rpc_guards(base, "/api/auth/me", "grpc", "proto/api/notes.proto", 16).should eq(["auth"])
    rpc_guards(base, "/api/notes/{name}", "grpc", "proto/api/notes.proto", 26).should eq(["auth"])
    rpc_guards(base, "/api/auth/signin", "grpc", "proto/api/notes.proto", 9).should be_empty
    rpc_guards(base, "/api/notes", "grpc", "proto/api/notes.proto", 22).should be_empty
  end

  it "leaves another proto package alone" do
    rpc_guards(base, "/billing.v1.InvoiceService/List", file: "server/api/server.go", line: 27).should be_empty
  end

  it "reads a grpc-go interceptor that skips the listed methods before checking the token" do
    with_go_tree({
      "go.mod"    => "module example.com/svc\n",
      "server.go" => <<-GO,
        package main

        import (
            "context"

            "google.golang.org/grpc"
            "google.golang.org/grpc/codes"
            "google.golang.org/grpc/status"
        )

        var publicMethods = map[string]bool{
            "/svc.v1.AccountService/Login": true,
        }

        func authUnary(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
            if publicMethods[info.FullMethod] {
                return handler(ctx, req)
            }
            if !hasToken(ctx) {
                return nil, status.Error(codes.Unauthenticated, "missing token")
            }
            return handler(ctx, req)
        }

        func main() {
            grpc.NewServer(grpc.UnaryInterceptor(authUnary))
        }
        GO
    }) do |dir|
      rpc_guards(dir, "/svc.v1.AccountService/Login").should be_empty
      rpc_guards(dir, "/svc.v1.AccountService/Delete").should eq(["auth"])
    end
  end

  it "reads a deny-list as guarding only the procedures it names" do
    with_go_tree({
      "go.mod"    => "module example.com/svc\n",
      "server.go" => <<-GO,
        package main

        import (
            "context"
            "slices"

            "google.golang.org/grpc"
            "google.golang.org/grpc/codes"
            "google.golang.org/grpc/status"
        )

        var adminMethods = []string{
            "/svc.v1.AccountService/Purge",
        }

        func isAdminMethod(m string) bool {
            return slices.Contains(adminMethods, m)
        }

        func adminUnary(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
            if isAdminMethod(info.FullMethod) && !isAdmin(ctx) {
                return nil, status.Error(codes.PermissionDenied, "admin only")
            }
            return handler(ctx, req)
        }

        func main() {
            grpc.NewServer(grpc.ChainUnaryInterceptor(adminUnary))
        }
        GO
    }) do |dir|
      rpc_guards(dir, "/svc.v1.AccountService/Purge").should eq(["authz"])
      rpc_guards(dir, "/svc.v1.AccountService/Login").should be_empty
    end
  end

  it "ignores a list whose test refuses nothing, or that no interceptor reaches" do
    with_go_tree({
      "go.mod"    => "module example.com/svc\n",
      "server.go" => <<-GO,
        package main

        import (
            "context"
            "log"

            "google.golang.org/grpc"
            "google.golang.org/grpc/codes"
            "google.golang.org/grpc/status"
        )

        var knownMethods = map[string]bool{
            "/svc.v1.AccountService/Login": true,
        }

        var auditedMethods = map[string]bool{
            "/svc.v1.AccountService/Login": true,
        }

        // Logs unknown procedures; lets everything through.
        func logUnary(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
            if !knownMethods[info.FullMethod] {
                log.Printf("unknown method %s", info.FullMethod)
            }
            return handler(ctx, req)
        }

        // A CLI check, never installed as an interceptor.
        func checkCLI(method string) error {
            if !auditedMethods[method] {
                return status.Error(codes.Unauthenticated, "not audited")
            }
            return nil
        }
        GO
    }) do |dir|
      rpc_guards(dir, "/svc.v1.AccountService/Delete").should be_empty
    end
  end
end
