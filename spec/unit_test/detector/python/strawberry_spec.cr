require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Strawberry" do
  options = create_test_options
  instance = Detector::Python::Strawberry.new options

  it "import strawberry" do
    instance.detect("schema.py", "import strawberry\n\n@strawberry.type\nclass Query: ...").should be_true
  end

  it "from strawberry.fastapi import" do
    instance.detect("main.py", "from strawberry.fastapi import GraphQLRouter").should be_true
  end

  it "import strawberry_django" do
    instance.detect("types.py", "import strawberry_django").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# strawberry jam\nimport flask").should be_false
  end

  it "non-python extension" do
    instance.detect("schema.txt", "import strawberry").should be_false
  end
end
