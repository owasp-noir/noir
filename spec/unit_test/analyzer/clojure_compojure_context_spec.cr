require "../../spec_helper"
require "file_utils"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/clojure/compojure"

private def compojure_routes(files : Hash(String, String)) : Array(String)
  temp_dir = File.tempname("compojure_context_test")
  CodeLocator.instance.clear_all
  files.each do |name, content|
    path = File.join(temp_dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  Analyzer::Clojure::Compojure.new(options).analyze.map { |e| "#{e.method} #{e.url}" }.sort!
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "Compojure context mounts" do
  it "mounts a defroutes named by a context under its path, not at the root" do
    compojure_routes({
      "src/app/users.clj" => <<-CLJ,
        (ns app.users
          (:require [compojure.core :refer :all]))

        (defroutes user-routes
          (GET "/" [] "list")
          (DELETE "/:id" [id] "gone"))

        (defroutes admin-routes
          (GET "/stats" [] "stats"))
        CLJ
      "src/app/handler.clj" => <<-CLJ,
        (ns app.handler
          (:require [compojure.core :refer :all]
                    [app.users :refer [user-routes admin-routes]]))

        (defroutes app-routes
          (GET "/" [] "home")
          (context "/users" [] user-routes)
          (context "/admin" [] admin-routes))

        (def app (routes admin-routes app-routes))
        CLJ
    }).should eq([
      "DELETE /users/:id", "GET /", "GET /admin/stats", "GET /stats", "GET /users",
    ])
  end
end
