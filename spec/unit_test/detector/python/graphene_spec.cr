require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Graphene" do
  options = create_test_options
  instance = Detector::Python::Graphene.new options

  it "import graphene" do
    instance.detect("schema.py", "import graphene\n\nclass Query(graphene.ObjectType): ...").should be_true
  end

  it "from graphene_django.views import" do
    instance.detect("urls.py", "from graphene_django.views import GraphQLView").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# graphene sheets\nimport flask").should be_false
  end

  it "non-python extension" do
    instance.detect("schema.txt", "import graphene").should be_false
  end
end
