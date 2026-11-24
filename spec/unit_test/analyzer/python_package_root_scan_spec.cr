require "../../spec_helper"
require "../../../src/models/noir"

private FIXTURES = File.expand_path("../../functional_test/fixtures/python/package_root_scan", __DIR__)

# Scans `target` from the working directory `cwd`, as a user would type it:
# `noir scan myapp` beside the package and `noir scan .` inside it spell
# the package's parent as `.` or `..`, which absolute paths never do.
private def scan_from(cwd : String, target : String) : Array(Endpoint)
  Dir.cd(cwd) { scan_dir(target) }
end

private def scan_dir(dir : String) : Array(Endpoint)
  CodeLocator.instance.clear_all
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  options["all_taggers"] = YAML::Any.new(true)
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

# What a scan reports, without the file paths that differ by base.
private def signature(endpoints : Array(Endpoint)) : Array(String)
  endpoints.map do |endpoint|
    params = endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!
    tags = endpoint.tags.map do |tag|
      clauses = tag.requires.try(&.map(&.any_of.map(&.to_s).join("|")).join("&"))
      "#{tag.name}=#{clauses}"
    end.sort!
    "#{endpoint.method} #{endpoint.url} #{params} #{tags}"
  end.sort!
end

private def endpoint_at(endpoints : Array(Endpoint), method : String, url : String) : Endpoint
  endpoints.find { |ep| ep.method == method && ep.url == url } ||
    fail "no #{method} #{url} in #{endpoints.map { |ep| "#{ep.method} #{ep.url}" }}"
end

describe "Python scan rooted at a package directory" do
  it "follows FastAPI imports that name the package the same as from its parent" do
    parent = scan_from("#{FIXTURES}/fastapi", ".")
    package = scan_from("#{FIXTURES}/fastapi", "myapp")

    signature(package).should eq(signature(parent))
    signature(scan_from("#{FIXTURES}/fastapi/myapp", ".")).should eq(signature(parent))
    signature(scan_dir("#{FIXTURES}/fastapi/myapp")).should eq(signature(parent))
    users = endpoint_at(package, "GET", "/api/v1/auth/users")
    users.tags.map(&.name).should contain("auth")
  end

  it "keeps a Django project's dotted includes, views and DRF defaults" do
    parent = scan_from("#{FIXTURES}/django", ".")
    package = scan_from("#{FIXTURES}/django", "shop")

    signature(package).should eq(signature(parent))
    signature(scan_from("#{FIXTURES}/django/shop", ".")).should eq(signature(parent))
    signature(scan_dir("#{FIXTURES}/django/shop")).should eq(signature(parent))
    endpoint_at(package, "GET", "/orders/<int:pk>/")
    endpoint_at(package, "GET", "/api/items/")
    endpoint_at(package, "POST", "/profile/").params.map(&.name).should contain("name")
    package.none? { |ep| ep.url == "/<int:pk>/" || ep.url == "/orders/" }.should be_true
  end

  it "follows a Flask blueprint import that names the package" do
    parent = scan_from("#{FIXTURES}/flask", ".")
    package = scan_from("#{FIXTURES}/flask", "webapp")

    signature(package).should eq(signature(parent))
    signature(scan_from("#{FIXTURES}/flask/webapp", ".")).should eq(signature(parent))
    endpoint_at(package, "GET", "/admin/reports")
  end
end
