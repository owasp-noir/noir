require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Mux" do
  options = create_test_options
  instance = Detector::Go::Mux.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gorilla/mux").should be_true
  end

  it "go.mod declaring only the minio/mux fork" do
    instance.detect("go.mod", "github.com/minio/mux v1.9.2").should be_true
  end

  it "go.mod without any mux dependency" do
    instance.detect("go.mod", "github.com/go-chi/chi/v5 v5.0.0").should be_false
  end
end
