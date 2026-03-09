require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java JSP" do
  options = create_test_options
  instance = Detector::Java::Jsp.new options

  it "detects .jsp file" do
    instance.detect("1.jsp", "<% info(); %>").should be_true
  end

  it "detects web.xml with <jsp-file>" do
    content = <<-XML
      <servlet>
        <servlet-name>index</servlet-name>
        <jsp-file>/index.jsp</jsp-file>
      </servlet>
      XML
    instance.detect("WEB-INF/web.xml", content).should be_true
  end

  it "detects web.xml with JspServlet" do
    content = <<-XML
      <servlet>
        <servlet-name>jsp</servlet-name>
        <servlet-class>org.apache.jasper.servlet.JspServlet</servlet-class>
      </servlet>
      XML
    instance.detect("WEB-INF/web.xml", content).should be_true
  end

  it "detects .java with javax.servlet.jsp" do
    content = "import javax.servlet.jsp.JspWriter;"
    instance.detect("MyServlet.java", content).should be_true
  end

  it "detects .java with jakarta.servlet.jsp" do
    content = "import jakarta.servlet.jsp.JspWriter;"
    instance.detect("MyServlet.java", content).should be_true
  end

  it "does not detect pom.xml with javax.servlet.jsp dependency" do
    content = <<-XML
      <dependency>
        <groupId>javax.servlet.jsp</groupId>
        <artifactId>javax.servlet.jsp-api</artifactId>
        <version>2.3.3</version>
      </dependency>
      XML
    instance.detect("pom.xml", content).should be_false
  end

  it "does not detect generic xml with servlet and .jsp strings" do
    content = <<-XML
      <config>
        <servlet-api>javax.servlet.jsp-api</servlet-api>
        <description>Handles .jsp pages</description>
      </config>
      XML
    instance.detect("config.xml", content).should be_false
  end

  it "does not detect xml with JspServlet outside servlet-class tag" do
    content = <<-XML
      <config>
        <description>Uses JspServlet for docs</description>
      </config>
      XML
    instance.detect("config.xml", content).should be_false
  end

  it "does not detect non-JSP files" do
    instance.detect("index.html", "<html></html>").should be_false
    instance.detect("app.js", "console.log('hello')").should be_false
  end
end
