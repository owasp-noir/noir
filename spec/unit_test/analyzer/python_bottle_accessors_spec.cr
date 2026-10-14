require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

private def scan_bottle(source : String) : Array(Endpoint)
  root = File.tempname("noir-bottle-accessors")
  FileUtils.mkdir_p(root)
  File.write(File.join(root, "requirements.txt"), "bottle\n")
  File.write(File.join(root, "app.py"), source)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(root) if root && Dir.exists?(root)
end

private def param_set(endpoint : Endpoint?) : Array(String)
  endpoint.not_nil!.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!
end

describe "Bottle request accessors" do
  it "reads params, GET, POST, files and get_header" do
    endpoints = scan_bottle(<<-PY)
      from bottle import Bottle, request

      app = Bottle()

      @app.route("/login", method="POST")
      def login():
          user = request.params.get("username")
          pw = request.POST.get("password")
          nxt = request.GET.get("next")
          lang = request.get_header("Accept-Language")
          avatar = request.files.get("avatar")
          return {}
      PY

    param_set(endpoints.find { |e| e.url == "/login" && e.method == "POST" }).should eq(
      ["Accept-Language:header", "avatar:form", "next:query", "password:form", "username:query"])
  end

  it "keeps form params off the GET side of a multi-method route" do
    endpoints = scan_bottle(<<-PY)
      from bottle import Bottle, request

      app = Bottle()

      @app.route("/users/<user_id:int>", method=["GET", "POST"])
      def user(user_id):
          name = request.forms.get("name")
          page = request.query.page
          return {}
      PY

    param_set(endpoints.find { |e| e.method == "GET" }).should eq(["page:query", "user_id:path"])
    param_set(endpoints.find { |e| e.method == "POST" }).should eq(["name:form", "page:query", "user_id:path"])
  end
end
