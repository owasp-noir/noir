require "../../spec_helper"
require "../../../src/models/analyzer_failure"

describe AnalyzerFailure do
  it "round-trips through JSON" do
    failure = AnalyzerFailure.new("go_gin", "Index out of bounds")

    json = failure.to_json
    json.should eq(%({"tech":"go_gin","message":"Index out of bounds"}))

    restored = AnalyzerFailure.from_json(json)
    restored.tech.should eq("go_gin")
    restored.message.should eq("Index out of bounds")
  end

  it "round-trips through YAML" do
    failure = AnalyzerFailure.new("python_django", "unterminated string literal")

    restored = AnalyzerFailure.from_yaml(failure.to_yaml)
    restored.tech.should eq("python_django")
    restored.message.should eq("unterminated string literal")
  end
end
