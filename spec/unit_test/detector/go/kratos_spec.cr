require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Kratos" do
  options = create_test_options
  instance = Detector::Go::Kratos.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/go-kratos/kratos/v2 v2.9.2").should be_true
  end

  it "go.mod with the newer v3 module path" do
    instance.detect("go.mod", "github.com/go-kratos/kratos/v3 v3.0.0").should be_true
  end

  it "a .go file importing the http transport sub-package" do
    content = <<-GO
      import (
        http "github.com/go-kratos/kratos/v2/transport/http"
      )
      GO
    instance.detect("server.go", content).should be_true
  end

  it "an unrelated .go file" do
    content = <<-GO
      import (
        "github.com/gin-gonic/gin"
      )
      GO
    instance.detect("server.go", content).should be_false
  end
end
