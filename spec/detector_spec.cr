require "../src/detector/absolute/*"
require "../src/detector/relative/*"

describe "Detect Ruby Rails" do
  it "detect_rails 1" do
    detect_ruby_rails("Gemfile", "gem 'rails'").should eq(true)
  end
  it "detect_rails 2" do
    detect_ruby_rails("Gemfile", "gem \"rails\"").should eq(true)
  end
end

describe "Detect Ruby Sinatra" do
  it "detect_sinatra 1" do
    detect_ruby_sinatra("Gemfile", "gem 'sinatra'").should eq(true)
  end
  it "detect_sinatra 2" do
    detect_ruby_sinatra("Gemfile", "gem \"sinatra\"").should eq(true)
  end
end

describe "Detect Go Echo" do
  it "detect_echo 1" do
    detect_go_echo("go.mod", "github.com/labstack/echo").should eq(true)
  end
end

describe "Detect Java JSP" do
  it "detect_jsp 1" do
    detect_java_jsp("1.jsp", "<% info(); %>").should eq(true)
  end
end

describe "Detect Java Spring" do
  it "detect_spring 1" do
    detect_java_spring("pom.xml", "org.springframework").should eq(true)
  end
end

describe "Detect PHP Pure" do
  it "detect_php 1" do
    detect_php_pure("1.php", "<? phpinfo(); ?>").should eq(true)
  end

  it "detect_php 2" do
    detect_php_pure("admin.php", "<?php TITLE!!! ?>").should eq(true)
  end
end
