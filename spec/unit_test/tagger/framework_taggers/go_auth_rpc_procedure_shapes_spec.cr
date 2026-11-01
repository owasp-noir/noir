require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

# Interceptor shapes that read like a procedure allow-list but are not one,
# or are one with a twist (see `GoRpcProcedureGate`).
private def shape_tags(base : String, procedure : String) : Array(String)
  CodeLocator.instance.clear_all
  Dir.glob("#{base}/**/*.{go,proto}").each { |f| CodeLocator.instance.register_path(f) }
  options = create_test_options
  options["base"] = YAML::Any.new(base)
  details = Details.new(PathInfo.new("#{base}/server.go", 1))
  details.technology = "go_connect_rpc"
  endpoint = Endpoint.new(procedure, "POST", [] of Param, details)
  GoAuthTagger.new(options).perform([endpoint]).first.tags.select(&.name.in?("auth", "authz", "anonymous")).map do |tag|
    tag.description.includes?("a setting") ? "#{tag.name}*" : tag.name
  end
end

private def with_rpc_shape(code : String, proto : String = "", &)
  dir = File.tempname("rpc_shape")
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "go.mod"), "module example.com/svc\n")
  File.write(File.join(dir, "server.go"), code)
  File.write(File.join(dir, "svc.proto"), proto) unless proto.empty?
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

RPC_SHAPE_LIST = <<-GO
  var PublicMethods = map[string]bool{
      "/svc.v1.AuthService/SignIn": true,
  }
  GO

# A grpc-go unary interceptor with `body`, installed.
private def unary_shape(body : String, list : String = RPC_SHAPE_LIST, install : String = "grpc.UnaryInterceptor(AuthUnary)") : String
  <<-GO
    package main

    #{list}

    func AuthUnary(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    #{body}
    }

    func main() {
        s := grpc.NewServer(#{install})
        pb.RegisterAuthServiceServer(s, impl)
    }
    GO
end

describe "GoAuthTagger (RPC procedure gate shapes)" do
  it "does not read a comparison with an auth code as a refusal" do
    body = <<-GO
        if PublicMethods[info.FullMethod] {
            return handler(ctx, req)
        }
        resp, err := handler(ctx, req)
        if c := status.Code(err); c == codes.Unauthenticated {
            log.Printf("denied %s", info.FullMethod)
        }
        return resp, err
      GO
    with_rpc_shape(unary_shape(body)) { |dir| shape_tags(dir, "/svc.v1.AuthService/Delete").should be_empty }
  end

  it "does not read a counter under a negated test as a refusal" do
    body = <<-GO
        resp, err := handler(ctx, req)
        if !PublicMethods[info.FullMethod] {
            if status.Code(err) == codes.Unauthenticated {
                failures++
            }
        }
        return resp, err
      GO
    with_rpc_shape(unary_shape(body)) { |dir| shape_tags(dir, "/svc.v1.AuthService/Delete").should be_empty }
  end

  it "reads a block that returns a check's error as a stricter check on the listed procedures" do
    list = %(var AdminMethods = map[string]bool{\n    "/svc.v1.NoteService/Delete": true,\n})
    body = <<-GO
        if AdminMethods[info.FullMethod] {
            if err := requireAdmin(ctx); err != nil {
                return nil, err
            }
        }
        if tokenMissing(ctx) {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body, list)) do |dir|
      shape_tags(dir, "/svc.v1.NoteService/Delete").should eq(["auth"])
      shape_tags(dir, "/svc.v1.NoteService/List").should be_empty
    end
  end

  it "reads a helper's inverted return and a negated group" do
    list = %(var publicMethods = map[string]struct{}{\n    "/svc.v1.AuthService/SignIn": {},\n}\n\nfunc requiresAuth(p string) bool {\n    _, ok := publicMethods[p]\n    return !ok\n})
    body = <<-GO
        if requiresAuth(info.FullMethod) && missingToken(ctx) {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body, list)) do |dir|
      shape_tags(dir, "/svc.v1.AuthService/SignIn").should be_empty
      shape_tags(dir, "/svc.v1.AuthService/Delete").should eq(["auth"])
    end
    grouped = <<-GO
        if !(PublicMethods[info.FullMethod] || hasToken(ctx)) {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(grouped)) do |dir|
      shape_tags(dir, "/svc.v1.AuthService/SignIn").should be_empty
      shape_tags(dir, "/svc.v1.AuthService/Delete").should eq(["auth"])
    end
  end

  it "reads a helper whose return it cannot evaluate as no gate" do
    list = RPC_SHAPE_LIST + "\nfunc check(p string) bool {\n    if PublicMethods[p] {\n        return true\n    }\n    return other(p)\n}"
    body = <<-GO
        if !check(info.FullMethod) {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body, list)) { |dir| shape_tags(dir, "/svc.v1.AuthService/Delete").should be_empty }
  end

  it "treats a role map's empty entries as public" do
    list = %(var MethodRoles = map[string]string{\n    "/svc.v1.AuthService/SignIn": "",\n    "/svc.v1.NoteService/Delete": "admin",\n})
    body = <<-GO
        if role := MethodRoles[info.FullMethod]; role != "" && !hasRole(ctx, role) {
            return nil, status.Error(codes.PermissionDenied, "forbidden")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body, list)) do |dir|
      shape_tags(dir, "/svc.v1.AuthService/SignIn").should be_empty
      shape_tags(dir, "/svc.v1.NoteService/Delete").should eq(["authz"])
      shape_tags(dir, "/svc.v1.NoteService/List").should be_empty
    end
  end

  it "leaves a streaming rpc open under a unary-only interceptor" do
    proto = "syntax = \"proto3\";\npackage svc.v1;\nservice AuthService {\n  rpc Watch(Empty) returns (stream Event);\n  rpc Delete(Empty) returns (Empty);\n}\n"
    body = <<-GO
        if !PublicMethods[info.FullMethod] {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body), proto) do |dir|
      shape_tags(dir, "/svc.v1.AuthService/Watch").should be_empty
      shape_tags(dir, "/svc.v1.AuthService/Delete").should eq(["auth"])
    end
  end

  it "needs the interceptor installed, and skips a service registered on a bare server" do
    body = <<-GO
        if !PublicMethods[info.FullMethod] {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body, install: "")) { |dir| shape_tags(dir, "/svc.v1.AuthService/Delete").should be_empty }
    bare = unary_shape(body) + "\nfunc admin() {\n    s := grpc.NewServer()\n    pb.RegisterNoteServiceServer(s, impl)\n}\n"
    with_rpc_shape(bare) do |dir|
      shape_tags(dir, "/svc.v1.NoteService/Delete").should be_empty
      shape_tags(dir, "/svc.v1.AuthService/Delete").should eq(["auth"])
    end
  end

  it "says when a setting decides the guard" do
    body = <<-GO
        if cfg.RequireAuth && !PublicMethods[info.FullMethod] {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body)) { |dir| shape_tags(dir, "/svc.v1.AuthService/Delete").should eq(["auth*"]) }
  end

  it "notes a public procedure a later check can still refuse, unless a narrower list exempts it" do
    code = <<-GO
      package api

      var PublicMethods = map[string]struct{}{
          "/svc.v1.AuthService/SignIn": {},
          "/svc.v1.NoteService/List":   {},
      }

      var BootstrapMethods = map[string]struct{}{
          "/svc.v1.AuthService/SignIn": {},
      }

      func IsPublic(p string) bool {
          _, ok := PublicMethods[p]
          return ok
      }

      func IsBootstrap(p string) bool {
          _, ok := BootstrapMethods[p]
          return ok
      }

      func (a *Authorizer) CheckAccess(ctx context.Context, p string, r *Result) error {
          if r != nil {
              return nil
          }
          if !IsPublic(p) {
              return ErrUnauthenticated
          }
          if IsBootstrap(p) {
              return nil
          }
          if a.allowsAnonymous(ctx) {
              return nil
          }
          return ErrUnauthenticated
      }

      type AuthInterceptor struct{ a *Authorizer }

      func NewAuthInterceptor(a *Authorizer) *AuthInterceptor {
          return &AuthInterceptor{a: a}
      }

      func (in *AuthInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
          return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
              if err := in.a.CheckAccess(ctx, req.Spec().Procedure, nil); err != nil {
                  return nil, err
              }
              return next(ctx, req)
          }
      }

      func handler() {
          _ = connect.WithInterceptors(NewAuthInterceptor(&Authorizer{}))
      }
      GO
    with_rpc_shape(code) do |dir|
      shape_tags(dir, "/svc.v1.NoteService/Delete").should eq(["auth"])
      shape_tags(dir, "/svc.v1.NoteService/List").should eq(["anonymous*"])
      shape_tags(dir, "/svc.v1.AuthService/SignIn").should be_empty
    end
  end

  it "keeps open what an earlier pass lets through" do
    body = <<-GO
        if strings.HasPrefix(info.FullMethod, "/svc.v1.HealthService/") {
            return handler(ctx, req)
        }
        switch info.FullMethod {
        case "/svc.v1.NoteService/List":
            return handler(ctx, req)
        }
        if !PublicMethods[info.FullMethod] {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body)) do |dir|
      shape_tags(dir, "/svc.v1.HealthService/Check").should be_empty
      shape_tags(dir, "/svc.v1.NoteService/List").should be_empty
      shape_tags(dir, "/svc.v1.NoteService/Delete").should eq(["auth"])
    end
  end

  it "survives thousands of bool helpers over one list" do
    helpers = (1..3000).map { |i| "func isPublic#{i}(p string) bool {\n    return PublicMethods[p]\n}" }.join("\n\n")
    body = <<-GO
        if !isPublic1(info.FullMethod) {
            return nil, status.Error(codes.Unauthenticated, "login")
        }
        return handler(ctx, req)
      GO
    with_rpc_shape(unary_shape(body, RPC_SHAPE_LIST + "\n" + helpers)) do |dir|
      shape_tags(dir, "/svc.v1.AuthService/Delete").should eq(["auth"])
    end
  end
end
