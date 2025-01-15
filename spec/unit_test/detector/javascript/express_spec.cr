require "../../../../src/detector/detectors/*"

describe "Detect JS Express" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Javascript::Express.new options

  it "require_single_quot" do
    instance.detect("index.js", "require('express')").should eq(true)
  end

  it "require_double_quot" do
    instance.detect("index.js", "require(\"express\")").should eq(true)
  end

  it "import_single_quot" do
    instance.detect("index.js", "import express from 'express'").should eq(true)
  end

  it "import_double_quot" do
    instance.detect("index.js", "import express from \"express\"").should eq(true)
  end

  it "const_require_single_quot" do
    instance.detect("index.js", "const express = require('express')").should eq(true)
  end

  it "const_require_double_quot" do
    instance.detect("index.js", "const express = require(\"express\")").should eq(true)
  end

  it "let_require_single_quot" do
    instance.detect("index.js", "let express = require('express')").should eq(true)
  end

  it "let_require_double_quot" do
    instance.detect("index.js", "let express = require(\"express\")").should eq(true)
  end

  it "var_require_single_quot" do
    instance.detect("index.js", "var express = require('express')").should eq(true)
  end

  it "var_require_double_quot" do
    instance.detect("index.js", "var express = require(\"express\")").should eq(true)
  end

  it "import_router_single_quot" do
    instance.detect("index.js", "import { Router } from 'express'").should eq(true)
  end

  it "import_router_double_quot" do
    instance.detect("index.js", "import { Router } from \"express\"").should eq(true)
  end

  it "app_use_express_json" do
    instance.detect("index.js", "app.use(express.json())").should eq(true)
  end

  it "app_use_express_urlencoded" do
    instance.detect("index.js", "app.use(express.urlencoded({ extended: true }))").should eq(true)
  end
end
