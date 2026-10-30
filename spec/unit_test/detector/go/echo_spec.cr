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
    # cmd/go reads only `indirect` alone or `indirect; …` as the marker.
    instance.detect("go.mod", "require github.com/labstack/echo/v4 v4.13.3 // indirectly via plugin\n").should be_true
    instance.detect("go.mod", "require github.com/labstack/echo/v4 v4.13.3 // indirect foo\n").should be_true
  end

  it "detects a .go import when go.mod still marks echo indirect" do
    instance.detect("main.go", %(package main\n\nimport "github.com/labstack/echo/v4"\n)).should be_true
    instance.detect("main.go", %(/* License */\npackage main\n\nimport (\n\t"net/http"\n\n\tmw "github.com/labstack/echo/v4"\n)\n)).should be_true
    # A `)` in a comment does not close the import block.
    instance.detect("main.go", %(package main\n\nimport (\n\t"net/http" // stdlib (HTTP)\n\t"github.com/labstack/echo/v4"\n)\n)).should be_true
    instance.detect("main.go", %(package main\n\nimport (\n\t// helpers (internal)\n\tweb "github.com/labstack/echo/v4"\n)\n)).should be_true
  end

  it "does not read a mention or a file the build leaves out as an import" do
    import = %(package main\n\nimport "github.com/labstack/echo/v4"\n)
    instance.detect("doc.go", "// Works with routers such as github.com/labstack/echo.\npackage adapter\n").should be_false
    instance.detect("gen.go", %(package gen\n\nimport "fmt"\n\nconst t = `package main\n\nimport "github.com/labstack/echo/v4"\n`\n)).should be_false
    instance.detect("gen.go", %(package gen\n\nimport (\n\t// "github.com/labstack/echo/v4"\n\t"fmt"\n)\n)).should be_false
    instance.detect("gen.go", "//go:build ignore\n\n#{import}").should be_false
    instance.detect("lib_test.go", import).should be_false
    instance.detect("testdata/src/app/main.go", import).should be_false
    instance.detect("vendor/example.com/x/main.go", import).should be_false
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
