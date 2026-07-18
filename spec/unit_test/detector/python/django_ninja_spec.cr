require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Django Ninja" do
  options = create_test_options
  instance = Detector::Python::DjangoNinja.new options

  it "from ninja import" do
    instance.detect("api.py", "from ninja import NinjaAPI, Router").should be_true
  end

  it "from ninja submodule import" do
    instance.detect("api.py", "from ninja.security import HttpBearer").should be_true
  end

  it "import ninja" do
    instance.detect("api.py", "import ninja").should be_true
  end

  it "import ninja submodule" do
    instance.detect("api.py", "import ninja.security").should be_true
  end

  it "ignores ninja_extra prefix collisions" do
    instance.detect("api.py", "from ninja_extra import api_controller").should be_false
  end

  it "non-python file" do
    instance.detect("ninja.txt", "from ninja import NinjaAPI").should be_false
  end

  it "unrelated python file" do
    instance.detect("views.py", "from django.http import JsonResponse").should be_false
  end
end
