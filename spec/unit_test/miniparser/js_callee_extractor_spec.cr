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

  it "keys multiline chained route callees by the call start line" do
    source = <<-JS
      app
        .get('/split', async (req, res) => {
          return res.json(await loadSplit())
        })
      JS

    callees = Noir::JSCalleeExtractor.callees_for_routes(source, "app.js")
    route_callees = callees[Noir::JSCalleeExtractor.route_key("GET", "/split", 1)]
    route_callees.map(&.[0]).should eq([
      "res.json",
      "loadSplit",
    ])
    method_line_callees = callees[Noir::JSCalleeExtractor.route_key("GET", "/split", 2)]
    method_line_callees.map(&.[0]).should eq(route_callees.map(&.[0]))
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

    Noir::JSCalleeExtractor.exported_function_line(source, "GET").should eq(1)
    Noir::JSCalleeExtractor.exported_function_line(source, "DELETE").should eq(7)
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

  it "extracts callees from default Nitro/Nuxt event handlers" do
    source = <<-TS
      export default defineEventHandler((event: { foo: string, bar: number }): { ok: boolean, user: unknown } => {
        const body = await readBody(event)
        AuditLog.write(body)
        return serializeUser(body)
      })
      TS

    callees = Noir::JSCalleeExtractor.callees_for_default_event_handler(source, "server/api/users.post.ts", language: :typescript)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"readBody", 2},
      {"AuditLog.write", 3},
      {"serializeUser", 4},
    ])
  end

  it "extracts default event handlers through wrapper and handler aliases" do
    source = <<-JS
      import { defineEventHandler as h } from 'h3'

      const load = (event) => send(loadUser(event))
      const wrapped = h(load)
      export default wrapped
      JS

    callees = Noir::JSCalleeExtractor.callees_for_default_event_handler(source, "server/api/users.get.ts")
    callees.map { |name, _, line| {name, line} }.should eq([
      {"send", 3},
      {"loadUser", 3},
    ])
  end

  it "extracts default event handlers from default export clauses" do
    source = <<-JS
      export const ignored = defineEventHandler(() => ignoredCall())

      const handler = defineEventHandler((event) => {
        return send(loadUser(event))
      })

      export { handler as default }
      JS

    callees = Noir::JSCalleeExtractor.callees_for_default_event_handler(source, "server/api/users.get.ts")
    callees.map { |name, _, line| {name, line} }.should eq([
      {"send", 4},
      {"loadUser", 4},
    ])
  end

  it "extracts concise default event handler arrows" do
    source = <<-JS
      export default defineEventHandler(event => send(loadUser(event)))
      JS

    callees = Noir::JSCalleeExtractor.callees_for_default_event_handler(source, "server/api/users.get.ts")
    callees.map { |name, _, line| {name, line} }.should eq([
      {"send", 1},
      {"loadUser", 1},
    ])
  end

  it "detects event handler aliases from property assignments" do
    source = <<-JS
      const wrap = h3.defineEventHandler
      export default wrap((event) => send(loadUser(event)))
      JS

    callees = Noir::JSCalleeExtractor.callees_for_default_event_handler(source, "server/api/users.get.ts")
    callees.map { |name, _, line| {name, line} }.should eq([
      {"send", 2},
      {"loadUser", 2},
    ])
  end

  it "extracts cached default event handlers but skips unrelated default exports" do
    source = <<-JS
      function handler(event) {
        return send(loadUser(event))
      }

      export default defineCachedEventHandler(handler, { maxAge: 60 })
      JS

    callees = Noir::JSCalleeExtractor.callees_for_default_event_handler(source, "server/api/users.get.ts")
    callees.map { |name, _, line| {name, line} }.should eq([
      {"send", 2},
      {"loadUser", 2},
    ])

    Noir::JSCalleeExtractor.callees_for_default_event_handler("export default { setup() { track() } }", "server/api/users.get.ts").should be_empty
  end
end
