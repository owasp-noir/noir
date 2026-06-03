require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go go-zero" do
  options = create_test_options
  instance = Detector::Go::GoZero.new options

  it "go.mod with go-zero dependency" do
    instance.detect("go.mod", "github.com/zeromicro/go-zero").should be_true
  end

  it "go.mod without go-zero dependency" do
    instance.detect("go.mod", "github.com/gin-gonic/gin").should be_false
  end

  # A `.go` file importing go-zero detects too, so a microservice
  # sub-directory (whose go.mod lives at the monorepo root) is still
  # recognized when scanned on its own.
  it "go file importing go-zero" do
    instance.detect("internal/handler/routes.go", "github.com/zeromicro/go-zero/rest").should be_true
  end

  it "go file without go-zero import" do
    instance.detect("main.go", "github.com/gin-gonic/gin").should be_false
  end
end
