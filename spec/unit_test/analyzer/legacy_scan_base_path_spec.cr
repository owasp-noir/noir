require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# Convention filters ("this file is an `#include` fragment", "this
# component is a test suite") were applied to the absolute path, so the
# directory a checkout happened to live in decided whether its endpoints
# were reported at all. Both analyzers now match on the scan-base-relative
# path instead.
private def scan_tree(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

private def write_file(path : String, content : String)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

describe "legacy analyzers and the scan base path" do
  it "reports Classic ASP pages from a base path that contains an `inc` segment" do
    root = File.tempname("noir-asp-base")
    site = File.join(root, "inc", "site")

    begin
      write_file(File.join(site, "login.asp"), <<-ASP)
        <%@ Language="VBScript" %>
        <%
          Dim user
          user = Request.QueryString("user")
          Response.Write user
        %>
        ASP

      endpoints = scan_tree(site)
      urls = endpoints.select { |endpoint| endpoint.details.technology == "asp_classic" }.map(&.url)

      urls.should contain("/login.asp")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "reports CFML components from a base path that contains a `test` segment" do
    root = File.tempname("noir-cfml-base")
    app = File.join(root, "test", "app")

    begin
      write_file(File.join(app, "resources", "Echo.cfc"), <<-CFML)
        component extends="taffy.core.resource" taffy:uri="/echo" {

        	function get( string message = "" ) {
        		return representationOf( { "message" : arguments.message } );
        	}

        }
        CFML

      endpoints = scan_tree(app)
      urls = endpoints.select { |endpoint| endpoint.details.technology == "cfml_taffy" }.map(&.url)

      urls.should contain("/echo")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
