require "../src/detector/absolute/*"
require "../src/detector/relative/*"

describe "Detect Ruby Rails" do
  it "detect_rails gemfile/single_quot" do
    detect_ruby_rails("Gemfile", "gem 'rails'").should eq(true)
  end
  it "detect_rails gemfile/double_quot" do
    detect_ruby_rails("Gemfile", "gem \"rails\"").should eq(true)
  end
end

describe "Detect Ruby Sinatra" do
  it "detect_sinatra - gemfile/single_quot" do
    detect_ruby_sinatra("Gemfile", "gem 'sinatra'").should eq(true)
  end
  it "detect_sinatra gemfile/double_quot" do
    detect_ruby_sinatra("Gemfile", "gem \"sinatra\"").should eq(true)
  end
end

describe "Detect Go Echo" do
  it "detect_echo - go.mod" do
    detect_go_echo("go.mod", "github.com/labstack/echo").should eq(true)
  end
end

describe "Detect Java JSP" do
  it "detect_jsp 1" do
    detect_java_jsp("1.jsp", "<% info(); %>").should eq(true)
  end
end

describe "Detect Java Spring" do
  it "detect_spring - pom.xml" do
    detect_java_spring("pom.xml", "org.springframework").should eq(true)
  end
  it "detect_spring - build.gradle" do
    detect_java_spring("build.gradle", "'org.springframework.boot' version '2.6.2'").should eq(true)
  end
end

describe "Detect PHP Pure" do
  it "detect_php 1" do
    detect_php_pure("1.php", "<? phpinfo(); ?>").should eq(true)
  end

  it "detect_php 2" do
    detect_php_pure("admin.php", "<?php TITLE!!! ?>").should eq(true)
  end

  it "detect_php 3" do
    detect_php_pure("admin.js", "<? This is template ?>").should_not eq(true)
  end
end

describe "Detect Express" do
  it "detect_js_express - require_single_quot" do
    detect_js_express("index.js", "require('express')").should eq(true)
  end
  it "detect_js_express - require_double_quot" do
    detect_js_express("index.js", "require(\"express\")").should eq(true)
  end
end

describe "Detect Python Django" do
  it "detect_django - settings.py" do
    detect_python_django("settings.py", "from django.apps import AppConfig").should eq(true)
  end
end

describe "Detect Python Flask" do
  it "detect_flask - app.py" do
    detect_python_flask("app.py", "from flask import Flask").should eq(true)
  end
end
