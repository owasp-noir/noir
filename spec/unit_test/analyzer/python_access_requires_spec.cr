require "file_utils"
require "../../spec_helper"
require "../../../src/models/noir"

private FIXTURES = File.expand_path("../../functional_test/fixtures/python", __DIR__)

private def scan_fixture(name : String) : Array(Endpoint)
  scan_dir(File.join(FIXTURES, name))
end

# Writes `files` under a temp dir and scans it.
private def scan_sources(files : Hash(String, String)) : Array(Endpoint)
  root = File.tempname("python_requires")
  files.each do |name, source|
    Dir.mkdir_p(File.dirname(File.join(root, name)))
    File.write(File.join(root, name), source)
  end
  scan_dir(root)
ensure
  FileUtils.rm_rf(root) if root
end

private def scan_dir(dir : String) : Array(Endpoint)
  CodeLocator.instance.clear_all
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

# {tag name => its clauses as atoms} of the endpoint at `method url`, for
# the tags that carry a requirement.
private def requires_of(endpoints : Array(Endpoint), method : String, url : String) : Hash(String, Array(Array(String)))
  endpoint = endpoints.find! { |ep| ep.method == method && ep.url == url }
  endpoint.tags.select(&.requires).to_h do |tag|
    {tag.name, tag.requires.not_nil!.map(&.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s })}
  end
end

describe "Python analyzer requires" do
  it "reads Odoo's auth= on the guard tag and on odoo-auth" do
    endpoints = scan_fixture("odoo")
    requires_of(endpoints, "POST", "/shop/payment/validate").should eq({"auth" => [["authenticated"]], "odoo-auth" => [["authenticated"]]})
    requires_of(endpoints, "GET", "/shop").should eq({"odoo-auth" => [["anonymous"]]})
    requires_of(endpoints, "POST", "/xmlrpc/{service}").should eq({"odoo-auth" => [["anonymous"]]})
  end

  it "reads Frappe's whitelist as signed in unless it admits guests" do
    endpoints = scan_fixture("frappe")
    requires_of(endpoints, "POST", "/api/method/library_app.api.stats").should eq({"auth" => [["authenticated"]]})
    # `Document.insert` checks the doctype's create permission.
    insert = %(unresolved:frappe.get_doc({"doctype": "Book Issue", "book": book, "member": member, "due_date": due}).insert())
    requires_of(endpoints, "POST", "/api/method/library_app.api.issue_book").should eq({"auth" => [["authenticated"], [insert]]})
    requires_of(endpoints, "GET", "/api/method/library_app.api.search").should eq({"frappe-allow-guest" => [["anonymous"]]})
  end

  it "keeps a Chalice authorizer and API key unread past refusing anonymous callers" do
    endpoints = scan_fixture("chalice")
    requires_of(endpoints, "POST", "/orders").should eq({"auth" => [["authenticated"], ["unresolved:Chalice authorizer=authorizer"]]})
    requires_of(endpoints, "GET", "/keys").should eq({"auth" => [["authenticated"], ["unresolved:Chalice api_key_required=True"]]})
  end

  it "keeps checks the analyzers do not read unresolved" do
    odoo = scan_sources({
      "m/__manifest__.py"         => "{'name': 'm'}\n",
      "m/__init__.py"             => "from . import controllers\n",
      "m/controllers/__init__.py" => "from . import main\n",
      "m/controllers/main.py"     => <<-PY,
        from odoo import http
        from odoo.http import request

        AUTH = 'public'

        class Main(http.Controller):
            @http.route('/m/user', type='http', auth='user')
            def u(self):
                if not request.env.user.has_group('base.group_system'):
                    raise AccessError("no")
                return "x"

            @http.route('/m/var', type='http', auth=AUTH)
            def v(self):
                return "x"
        PY
    })
    requires_of(odoo, "GET", "/m/user")["auth"].should eq([["authenticated"],
                                                           ["unresolved:if not request.env.user.has_group('base.group_system'):"], [%(unresolved:raise AccessError("no"))]])
    requires_of(odoo, "GET", "/m/var").should eq({"odoo-auth" => [["unresolved:Odoo auth='AUTH'"]]})
    frappe = scan_sources({
      "app1/setup.py"         => "",
      "app1/app1/__init__.py" => "",
      "app1/app1/hooks.py"    => "app_name = 'app1'\n",
      "app1/app1/api.py"      => <<-PY,
        import frappe

        @frappe.whitelist()
        @role_required("Manager")
        def deco(x):
            ensure_manager()
            return x
        PY
    })
    requires_of(frappe, "GET", "/api/method/app1.api.deco").should eq({"auth" => [["authenticated"],
                                                                                  [%(unresolved:@role_required("Manager"))], ["unresolved:ensure_manager()"]]})
  end

  it "reads HomeAssistantView requires_auth as signed in" do
    requires_of(scan_fixture("aiohttp_ha_view"), "GET", "/api/config").should eq({"auth" => [["authenticated"]]})
  end

  it "names the permission a Flask-AppBuilder ModelRestApi route checks" do
    description = "flask-appbuilder ModelRestApi protect (a setting can make it public)"
    permission = "flask-appbuilder permission can_get on DashboardRestApi (method_permission_name or class_permission_name may rename it)"
    requires_of(scan_fixture("flask_appbuilder_inherited"), "GET", "/api/v1/dashboard/").should eq(
      {"auth" => [["authenticated", "unresolved:#{description}"], ["unresolved:#{description}", "unresolved:#{permission}"]]})
  end
end
