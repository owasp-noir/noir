require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go net/http (stdlib)" do
  options = create_test_options
  instance = Detector::Go::Http.new options

  it "detects on .go file with net/http import + HandleFunc" do
    content = <<-GO
      package main
      import "net/http"
      func main() {
          http.HandleFunc("/hello", handler)
      }
      GO
    instance.detect("main.go", content).should be_true
  end

  it "detects on .go file with alias + NewServeMux" do
    content = <<-GO
      package main
      import h "net/http"
      func main() {
          m := h.NewServeMux()
          m.HandleFunc("/api", h2)
      }
      GO
    instance.detect("main.go", content).should be_true
  end

  it "does not detect on .go that only uses net/http for types (e.g. handler signature)" do
    content = <<-GO
      package main
      import "net/http"
      func handler(w http.ResponseWriter, r *http.Request) {}
      GO
    instance.detect("main.go", content).should be_false
  end

  it "does not detect on go.mod (no stdlib entry)" do
    instance.detect("go.mod", "module example.com/app").should be_false
  end
end
