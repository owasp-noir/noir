require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Azure Functions function.json" do
  options = create_test_options
  instance = Detector::Specification::AzureFunctions.new options

  it "detects function.json with httpTrigger binding" do
    src = %({"bindings":[{"type":"httpTrigger","direction":"in","methods":["get"]}]})
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC

    instance.detect("MyFunc/function.json", src).should be_true
    locator.all(Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC).should eq ["MyFunc/function.json"]
  end

  it "rejects function.json without httpTrigger" do
    src = %({"bindings":[{"type":"queueTrigger"}]})
    instance.detect("Worker/function.json", src).should be_false
  end

  it "ignores unrelated filenames" do
    instance.detect("config.json", %({"bindings":[{"type":"httpTrigger"}]})).should be_false
  end
end

describe "Detect Azure Functions code-first triggers" do
  options = create_test_options
  instance = Detector::Specification::AzureFunctions.new options

  it "registers C#, Python v2 and Node v4 sources that declare an HTTP trigger" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC

    instance.detect("Functions/Api.cs", %([Function("A")] public R A([HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequestData r) { })).should be_true
    instance.detect("function_app.py", "import azure.functions as func\napp = func.FunctionApp()\n@app.route(route=\"a\")\ndef a(req):\n    pass\n").should be_true
    instance.detect("src/functions/a.ts", %(import { app } from "@azure/functions";\napp.http("a", { handler });)).should be_true
    locator.all(Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC).should eq ["Functions/Api.cs", "function_app.py", "src/functions/a.ts"]
  end

  it "rejects look-alike routes without the Azure Functions marker" do
    instance.detect("server.js", %(const app = require("express")();\napp.get("/a", h);)).should be_false
    instance.detect("app.py", "from flask import Flask\n@app.route('/a')\ndef a():\n    pass\n").should be_false
    instance.detect("Timer.cs", %([Function("T")] public void T([TimerTrigger("0 * * * * *")] TimerInfo t) { })).should be_false
  end
end
