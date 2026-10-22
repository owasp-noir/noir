require "../../func_spec.cr"

# `app.post('/upload', upload.single('file'), ensureFile, checkType,
# handleZip, handleXml, handleYaml)`: every step after the path runs for
# this route, and the zip write lives in `handleZip`, not in the last
# argument the route's handler is named after.
describe "Express route-specific handler chain callees", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads every app-defined step, handler first, and skips guards and packages" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_handler_chain/")])
    options["ai_context"] = YAML::Any.new(true)
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    upload = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/upload" }
    upload.handler.try(&.name).should eq("handleYaml")
    # The handler's own callees come first, then the steps nearest it.
    upload.callees.map(&.name).should eq([
      "req.file.buffer.toString", "res.status().send",                         # handleYaml
      "req.file.originalname.endsWith", "next", "parseXml",                    # handleXml
      "fs.writeFileSync", "res.status().end",                                  # handleZip
      "req.file.originalname.split().pop", "console.log", "res.status().json", # checkType, ensureFile
    ])
    upload.callees.each { |callee| callee.path.should_not(be_nil).should end_with("express_handler_chain/routes/upload.js") }
    # Only the step that writes adds a sink; the validators add none.
    upload.ai_context.should_not(be_nil).sinks.map { |sink| {sink.kind, sink.name} }.should eq([{"file_io", "fs.writeFileSync"}])

    # A guard-only registration has no handler for its steps to feed.
    guard_only = endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/upload" }
    guard_only.handler.should be_nil
    guard_only.callees.should be_empty

    notes = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/notes" }
    notes.callees.map(&.name).should eq(["res.send", "req.file.originalname.split().pop", "console.log", "next"])

    legacy = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/legacy-upload" }
    legacy.handler.try(&.name).should eq("handleYaml")
    legacy.callees.map(&.name).should eq(["req.file.buffer.toString", "res.status().send", "req.file.originalname.split().pop", "console.log", "next"])
  end
end
