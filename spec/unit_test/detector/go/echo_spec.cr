require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Echo" do
  options = create_test_options
  instance = Detector::Go::Echo.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/labstack/echo").should be_true
  end

  it "ignores // indirect dependencies in go.mod" do
    content = <<-MOD
      module example.com/myapp

      go 1.21

      require github.com/labstack/echo/v4 v4.13.3 // indirect
      MOD
    instance.detect("go.mod", content).should be_false
  end

  it "ignores //indirect with no space or with a trailing note" do
    instance.detect("go.mod", "require github.com/labstack/echo/v4 v4.13.3 //indirect\n").should be_false
    instance.detect("go.mod", "require github.com/labstack/echo/v4 v4.13.3 // indirect; used by tools\n").should be_false
    instance.detect("go.mod", "require github.com/labstack/echo/v4 v4.13.3 // pinned, not indirect\n").should be_true
  end

  it "detects a .go import when go.mod still marks echo indirect" do
    instance.detect("main.go", %(package main\n\nimport "github.com/labstack/echo/v4"\n)).should be_true
  end

  it "detects direct dependencies in go.mod" do
    content = <<-MOD
      module example.com/myapp

      go 1.21

      require (
        github.com/labstack/echo/v4 v4.13.3
        github.com/other/lib v1.0.0 // indirect
      )
      MOD
    instance.detect("go.mod", content).should be_true
  end
end
