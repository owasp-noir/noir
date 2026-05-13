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
end
