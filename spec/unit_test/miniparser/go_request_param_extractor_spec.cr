require "../../spec_helper"
require "../../../src/miniparsers/go_request_param_extractor"

describe Noir::GoRequestParamExtractor do
  describe "#package_function_bodies_for_dirs" do
    it "packages function bodies by directory" do
      contents = {
        "/app/main.go" => "package main\n\nfunc hello() {}\n",
      }
      dirs = Set{"/app"}

      result = Noir::GoRequestParamExtractor.package_function_bodies_for_dirs(contents, dirs)
      result.has_key?("/app").should be_true
      result["/app"].has_key?("hello").should be_true
    end
  end

  describe "#package_method_bodies_for_dirs" do
    it "packages method bodies by directory" do
      contents = {
        "/app/handler.go" => "package main\n\ntype H struct{}\nfunc (h *H) Serve() {}\n",
      }
      dirs = Set{"/app"}

      result = Noir::GoRequestParamExtractor.package_method_bodies_for_dirs(contents, dirs)
      result.has_key?("/app").should be_true
      result["/app"].has_key?("Serve").should be_true
    end
  end

  describe "#params_for_routes" do
    it "extracts query and header parameters from go handler" do
      source = <<-GO
        package main
        import "net/http"

        func main() {
            http.HandleFunc("/api", func(w http.ResponseWriter, r *http.Request) {
                q := r.URL.Query().Get("search")
                h := r.Header.Get("X-API-Key")
            })
        }
        GO

      # Row index for http.HandleFunc
      rows = Set{4}
      methods = {4 => "GET"}

      params_map = Noir::GoRequestParamExtractor.params_for_routes(
        source,
        rows,
        methods,
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new
      )

      params_map.has_key?(4).should be_true
      params = params_map[4]
      params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
      params.any? { |p| p.name == "X-API-Key" && p.param_type == "header" }.should be_true
    end
  end
end
