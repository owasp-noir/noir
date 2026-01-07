require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Express" do
  options = create_test_options
  instance = Detector::Javascript::Express.new options

  it "require_single_quot" do
    instance.detect("index.js", "require('express')").should be_true
  end

  it "require_double_quot" do
    instance.detect("index.js", "require(\"express\")").should be_true
  end

  it "import_single_quot" do
    instance.detect("index.js", "import express from 'express'").should be_true
  end

  it "import_double_quot" do
    instance.detect("index.js", "import express from \"express\"").should be_true
  end

  it "const_require_single_quot" do
    instance.detect("index.js", "const express = require('express')").should be_true
  end

  it "const_require_double_quot" do
    instance.detect("index.js", "const express = require(\"express\")").should be_true
  end

  it "let_require_single_quot" do
    instance.detect("index.js", "let express = require('express')").should be_true
  end

  it "let_require_double_quot" do
    instance.detect("index.js", "let express = require(\"express\")").should be_true
  end

  it "var_require_single_quot" do
    instance.detect("index.js", "var express = require('express')").should be_true
  end

  it "var_require_double_quot" do
    instance.detect("index.js", "var express = require(\"express\")").should be_true
  end

  it "import_router_single_quot" do
    instance.detect("index.js", "import { Router } from 'express'").should be_true
  end

  it "import_router_double_quot" do
    instance.detect("index.js", "import { Router } from \"express\"").should be_true
  end

  it "app_use_express_json" do
    instance.detect("index.js", "app.use(express.json())").should be_true
  end

  it "app_use_express_urlencoded" do
    instance.detect("index.js", "app.use(express.urlencoded({ extended: true }))").should be_true
  end
end
