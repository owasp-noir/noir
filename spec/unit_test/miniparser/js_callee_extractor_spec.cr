require "../../spec_helper"
require "../../../src/miniparsers/js_callee_extractor"

describe Noir::JSCalleeExtractor do
  it "does not duplicate receiver calls for fluent method invocations" do
    source = <<-JS
      app.post('/users/:id', async (req, res) => {
        await serviceFactory().save(req.body)
        res.send(await loadProfile())
      })
      JS

    callees = Noir::JSCalleeExtractor.callees_for_routes(source, "app.js")
    route_callees = callees[Noir::JSCalleeExtractor.route_key("POST", "/users/:id", 1)]
    route_callees.map(&.[0]).should eq([
      "serviceFactory().save",
      "res.send",
      "loadProfile",
    ])
  end

  it "extracts callees from a standalone function body with adjusted lines" do
    body = <<-JS

        const user = this.usersService.create(dto)
        AuditLog.write('create')
        return this.presenter.user(user)
      JS

    callees = Noir::JSCalleeExtractor.callees_for_function_body(body, "users.controller.ts", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"this.usersService.create", 11},
      {"AuditLog.write", 12},
      {"this.presenter.user", 13},
    ])
  end

  it "falls back for TypeScript-only syntax inside a method body" do
    body = <<-TS

        const dto = input as CreateUserDto
        return this.usersService.create(dto satisfies CreateUserDto)
      TS

    callees = Noir::JSCalleeExtractor.callees_for_function_body(body, "users.controller.ts", 20, language: :typescript)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"this.usersService.create", 22},
    ])
  end
end
