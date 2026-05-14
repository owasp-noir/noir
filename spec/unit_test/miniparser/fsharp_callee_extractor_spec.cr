require "../../spec_helper"
require "../../../src/miniparsers/fsharp_callee_extractor"

describe Noir::FsharpCalleeExtractor do
  it "extracts Giraffe chain handlers, applications, returns, and pipelines" do
    body = <<-FSHARP
      >=> handleLogin
      >=> fun next ctx ->
          task {
              let! user = UserService.load ctx
              AuditLog.write "show" user
              return! json (serializeUser user) next ctx
          }
      let response = loadPipeline ctx |> enrich |> renderPipeline
      json response next ctx
      FSHARP

    callees = Noir::FsharpCalleeExtractor.callees_for_body(body, "Program.fs", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"handleLogin", 10},
      {"UserService.load", 13},
      {"AuditLog.write", 14},
      {"json", 15},
      {"serializeUser", 15},
      {"loadPipeline", 17},
      {"enrich", 17},
      {"renderPipeline", 17},
      {"json", 18},
    ])
  end

  it "extracts generic dotted calls and routef-style bare handlers" do
    body = <<-FSHARP
      ctx.BindJsonAsync<Order>()
      handleUser
      ItemController.update
      FSHARP

    callees = Noir::FsharpCalleeExtractor.callees_for_body(body, "Program.fs", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"ctx.BindJsonAsync", 30},
      {"handleUser", 31},
      {"ItemController.update", 32},
    ])
  end

  it "skips comments, nested block comments, strings, triple strings, and reserved words" do
    body = <<-FSHARP
      let ignored = "Ignored.string()"
      let verbatim = @"Ignored.verbatim()"
      let triple = """
        Ignored.triple()
      """
      (* Ignored.block()
         (* Nested.block() *)
      *)
      // Ignored.line()
      Real.call "ok"
      FSHARP

    callees = Noir::FsharpCalleeExtractor.callees_for_body(body, "Program.fs", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"Real.call", 49},
    ])
  end

  it "does not report plain dotted property access as calls" do
    body = <<-FSHARP
      let path = ctx.Request.Path
      let name = ctx.User.Identity.Name
      let loaded = UserService.load ctx
      ctx.BindJsonAsync<Order>()
      FSHARP

    callees = Noir::FsharpCalleeExtractor.callees_for_body(body, "Program.fs", 60)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService.load", 62},
      {"ctx.BindJsonAsync", 63},
    ])
  end
end
