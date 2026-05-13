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

  it "extracts callees from exported handlers using the AST" do
    source = <<-JS
      export const GET = async ({ url }) => {
        const marker = "}"
        // }
        return json(loadUsers(marker))
      }

      const remove = async ({ params }) => json(deleteUser(params.id))
      export { remove as DELETE }
      JS

    get_callees = Noir::JSCalleeExtractor.callees_for_exported_function(source, "routes/+server.ts", "GET")
    get_callees.map { |name, _, line| {name, line} }.should eq([
      {"json", 4},
      {"loadUsers", 4},
    ])

    delete_callees = Noir::JSCalleeExtractor.callees_for_exported_function(source, "routes/+server.ts", "DELETE")
    delete_callees.map { |name, _, line| {name, line} }.should eq([
      {"json", 7},
      {"deleteUser", 7},
    ])
  end

  it "extracts callees from typed exported arrow handlers" do
    source = <<-TS
      import { type RequestHandler } from '@sveltejs/kit'

      export const POST: RequestHandler = async ({ request }) => {
        const body = await request.json()
        await serviceFactory().create(body)
      }
      TS

    callees = Noir::JSCalleeExtractor.callees_for_exported_function(source, "routes/+server.ts", "POST")
    callees.map { |name, _, line| {name, line} }.should eq([
      {"request.json", 4},
      {"serviceFactory().create", 5},
    ])
  end
end
