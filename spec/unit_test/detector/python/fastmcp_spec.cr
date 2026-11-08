require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python FastMCP" do
  options = create_test_options
  instance = Detector::Python::FastMCP.new options

  it "from fastmcp import FastMCP" do
    instance.detect("server.py", "from fastmcp import FastMCP\nmcp = FastMCP(\"demo\")").should be_true
  end

  it "from fastmcp.server.auth.providers.jwt import JWTVerifier" do
    instance.detect("auth.py", "from fastmcp.server.auth.providers.jwt import JWTVerifier").should be_true
  end

  it "from mcp.server.fastmcp import FastMCP" do
    instance.detect("server.py", "from mcp.server.fastmcp import FastMCP").should be_true
  end

  it "import fastmcp" do
    instance.detect("server.py", "import fastmcp").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# a fastmcp server lives elsewhere\nfrom starlette.applications import Starlette").should be_false
  end

  it "non-python extension" do
    instance.detect("server.txt", "from fastmcp import FastMCP").should be_false
  end
end
