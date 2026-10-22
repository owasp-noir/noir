require "../../spec_helper"
require "../../../src/miniparsers/go_request_param_extractor"

describe Noir::GoRequestParamExtractor do
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

  describe "#lazy_package_bodies_for_dirs" do
    it "builds tables only for the requested directories" do
      contents = {
        "/app/a.go"     => "package app\n\nfunc Shared() int { return 1 }\nfunc (s *S) Get() {}\n",
        "/app/b.go"     => "package app\n\nfunc Shared() int { return 2 }\nfunc Only() {}\nfunc (t *T) Get() {}\n",
        "/app/tab.go"   => "package app\n\nfunc\tTabbed() {}\n",
        "/app/sub/c.go" => "package sub\n\nfunc Sub() {}\n",
        "/other/d.go"   => "package other\n\nfunc Other() {}\n",
      }
      dirs = Set{"/app", "/app/sub"}

      lazy = Noir::GoRequestParamExtractor.lazy_package_bodies_for_dirs(contents, dirs)

      # `func ` gate: the tab-separated declaration is skipped.
      Noir::GoRequestParamExtractor.function_bodies_for_directory(lazy, "/app").keys.sort!.should eq(["Only", "Shared"])
      Noir::GoRequestParamExtractor.method_bodies_for_directory(lazy, "/app").keys.should eq(["Get"])
      Noir::GoRequestParamExtractor.function_bodies_for_directory(lazy, "/app/sub").keys.should eq(["Sub"])
      # Directories outside `dirs` answer empty without parsing.
      ["/other", "/missing"].each do |dir|
        Noir::GoRequestParamExtractor.function_bodies_for_directory(lazy, dir).should be_empty
        Noir::GoRequestParamExtractor.method_bodies_for_directory(lazy, dir).should be_empty
      end
      # First definition wins, methods on different receivers accumulate.
      lazy.functions_for("/app")["Shared"].file_path.should eq("/app/a.go")
      lazy.methods_for("/app")["Get"].size.should eq(2)
    end
  end
end
