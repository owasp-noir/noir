require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/engines/python_engine"

class PythonEngineSpecHarness < Analyzer::Python::PythonEngine
  def callees_from(body : String,
                   body_start_line : Int32,
                   path : String,
                   definition_base_path : String,
                   source : String) : Array(Callee)
    build_callees_from(
      body,
      body_start_line,
      path,
      definition_base_path: definition_base_path,
      source: source
    )
  end
end

describe Analyzer::Python::PythonEngine do
  it "treats singular Python test fixture directories as non-production code" do
    Analyzer::Python::PythonEngine.python_test_path?("/repo/wagtail/test/urls.py", "/repo/wagtail").should be_true
    Analyzer::Python::PythonEngine.python_test_path?("/repo/src/oscar/test/factories/urls.py", "/repo/src/oscar").should be_true
  end

  it "does not treat parent test directories outside the scan root as Python tests" do
    Analyzer::Python::PythonEngine.python_test_path?("/tmp/test/myapp/app/views.py", "/tmp/test/myapp").should be_false
    Analyzer::Python::PythonEngine.python_test_path?("/tmp/test/myapp/tests/views.py", "/tmp/test/myapp").should be_true
  end

  it "keeps call-site coordinates when a Python callee definition is unreachable" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)
    harness = PythonEngineSpecHarness.new(options)
    source = <<-PY
      def handler():
          unknown_call()
      PY
    body = source
    caller_path = "/tmp/noir-python-engine-spec/app.py"

    callees = harness.callees_from(
      body,
      0,
      caller_path,
      "/tmp/noir-python-engine-spec",
      source
    )

    callees.size.should eq(1)
    callees[0].name.should eq("unknown_call")
    callees[0].path.should eq(caller_path)
    callees[0].line.should eq(2)
  end
end
