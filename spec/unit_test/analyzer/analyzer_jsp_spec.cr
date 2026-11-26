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

describe "JSP JSON body extraction" do
  options = create_test_options
  instance = Analyzer::Java::Jsp.new(options)

  it "returns nil when the page does not read the request body" do
    instance.extract_json_body_params(%q(<%= request.getParameter("username") %>)).should be_nil
  end

  it "reports keys read from a body parsed off getInputStream" do
    content = <<-JSP
      <%@ page import="org.json.simple.JSONObject" %>
      <%@ page import="java.io.*" %>
      <%
          Reader reader = new InputStreamReader(request.getInputStream(), "UTF-8");
          JSONObject jsonObject = (JSONObject) new JSONParser().parse(reader);
          String secret = (String) jsonObject.get("secret");
          String orderId = (String) jsonObject.get("orderId");
      %>
      JSP
    params = instance.extract_json_body_params(content).not_nil!
    params.map(&.name).should eq(["secret", "orderId"])
    params.map(&.param_type).uniq!.should eq(["json"])
  end

  it "follows getReader through a StringBuilder and reports first-level keys only" do
    content = <<-JSP
      <%
          BufferedReader br = request.getReader();
          StringBuilder sb = new StringBuilder();
          String line;
          while ((line = br.readLine()) != null) {
              sb.append(line);
          }
          JSONObject event = new JSONObject(sb.toString());
          String eventType = event.getString("eventType");
          int retry = event.optInt("retry", 0);
          JSONObject data = event.getJSONObject("data");
          String paymentId = data.getString("paymentId");
      %>
      JSP
    instance.extract_json_body_params(content).not_nil!.map(&.name).should eq(["eventType", "retry", "data"])
  end

  it "reports no keys when the body is read but never parsed into an object" do
    content = %q(<% byte[] raw = request.getInputStream().readAllBytes(); String id = other.get("id"); %>)
    instance.extract_json_body_params(content).not_nil!.should be_empty
  end
end
