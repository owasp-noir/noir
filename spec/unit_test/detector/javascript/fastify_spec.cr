require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Fastify" do
  options = create_test_options
  instance = Detector::Javascript::Fastify.new options

  it "detects fastify require/import or calls" do
    instance.detect("server.js", "const fastify = require('fastify')()").should be_true
    instance.detect("server.ts", "import Fastify from 'fastify'").should be_true
    instance.detect("server.js", "fastify.get('/path', (req, reply) => {})").should be_true
  end
end
