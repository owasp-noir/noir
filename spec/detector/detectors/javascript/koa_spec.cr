require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/koa"

describe Detector::Javascript::Koa do
  it "detects koa in js files" do
    detector = Detector::Javascript::Koa.new
    # Test with require
    detector.detect("file.js", "const Koa = require('koa');").should be_true
    # Test with import
    detector.detect("file.mjs", "import Koa from 'koa';").should be_true
    # Test with new Koa()
    detector.detect("file.js", "const app = new Koa();").should be_true
    # Test with koa-router import
    detector.detect("file.js", "import Router from 'koa-router';").should be_true
    # Test with app.use() - common in Koa
    detector.detect("file.js", "app.use(async ctx => { ctx.body = 'Hello'; });").should be_true
    # Test with typescript file
    detector.detect("file.ts", "import Koa from 'koa';").should be_true
  end

  it "does not detect koa in unrelated files" do
    detector = Detector::Javascript::Koa.new
    detector.detect("file.js", "const express = require('express');").should be_false
    detector.detect("file.txt", "import Koa from 'koa';").should be_false
    detector.detect("another.js", "console.log('hello world');").should be_false
  end

  it "sets the name correctly" do
    detector = Detector::Javascript::Koa.new
    detector.name.should eq "js_koa"
  end
end
