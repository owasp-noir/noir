require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/aspnet_core_minimal_api"

describe "Detect ASP.NET Core Minimal API" do
  options = create_test_options
  instance = Detector::CSharp::AspNetCoreMinimalApi.new options

  it "detects verb mapped minimal routes" do
    source = <<-CS
      var app = WebApplication.CreateBuilder(args).Build();
      app.MapGet("/users", () => Results.Ok());
      CS

    instance.detect("Program.cs", source).should be_true
  end

  it "detects generic Map routes in a minimal API context" do
    source = <<-CS
      public static IEndpointRouteBuilder MapRoutes(this IEndpointRouteBuilder endpoints)
      {
          endpoints.Map("/fallback", () => Results.Ok());
          return endpoints;
      }
      CS

    instance.detect("Routes.cs", source).should be_true
  end

  it "does not detect Carter modules" do
    source = <<-CS
      public sealed class UsersModule : ICarterModule
      {
          public void AddRoutes(IEndpointRouteBuilder app)
          {
              app.MapGet("/users", () => Results.Ok());
          }
      }
      CS

    instance.detect("UsersModule.cs", source).should be_false
  end

  it "ignores project files without route declarations" do
    instance.detect("App.csproj", %(<Project Sdk="Microsoft.NET.Sdk.Web"></Project>)).should be_false
  end
end
