require "../../spec_helper"
require "../../../src/analyzer/analyzers/java/jsp.cr"

describe "JSP param extraction" do
  options = create_test_options
  instance = Analyzer::Java::Jsp.new(options)

  it "extracts getParameter as a query param" do
    params = instance.extract_params(%q(<%= request.getParameter("username") %>))
    params.map(&.name).should contain("username")
  end

  it "extracts a user-meaningful getAttribute as a query param" do
    params = instance.extract_params(%q(<% Object userId = request.getAttribute("userId"); %>))
    params.map(&.name).should contain("userId")
  end

  # Container/framework-managed request attributes are populated by the
  # servlet engine or filters, never by user input. They previously
  # leaked into the parameter list (e.g. `javax.servlet.request.*` on
  # TLS info JSPs) and must be filtered out.
  it "ignores container-managed servlet attributes" do
    content = <<-JSP
      <%= request.getAttribute("javax.servlet.request.ssl_session_id") %>
      <%= request.getAttribute("jakarta.servlet.request.X509Certificate") %>
      <%= request.getAttribute("org.springframework.web.servlet.HandlerMapping.bestMatchingPattern") %>
      JSP
    instance.extract_params(content).should be_empty
  end

  it "classifies known internal attribute namespaces" do
    instance.internal_servlet_attribute?("javax.servlet.request.key_size").should be_true
    instance.internal_servlet_attribute?("jakarta.servlet.forward.request_uri").should be_true
    instance.internal_servlet_attribute?("org.apache.catalina.something").should be_true
    instance.internal_servlet_attribute?("userId").should be_false
    instance.internal_servlet_attribute?("customAttribute").should be_false
  end
end
