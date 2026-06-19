require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Node http" do
  options = create_test_options
  instance = Detector::Javascript::Http.new options

  it "detects commonjs http createServer request branching" do
    content = <<-JS
      const http = require('http');
      http.createServer((req, res) => {
        if (req.method === 'GET' && req.url === '/api/users') res.end();
      });
      JS

    instance.detect("server.js", content).should be_true
  end

  it "detects node:https aliased TypeScript import" do
    content = <<-TS
      import { createServer as createHttpsServer } from 'node:https';
      createHttpsServer((request: IncomingMessage, response: ServerResponse) => {
        const parsed = new URL(request.url ?? '/', 'https://localhost');
        if (request.method === 'POST' && parsed.pathname === '/submit') response.end();
      });
      TS

    instance.detect("server.ts", content).should be_true
  end

  it "detects direct require createServer" do
    content = <<-JS
      require('node:http').createServer(function (req, res) {
        if (req.method == 'DELETE' && req.url == '/items') res.end();
      });
      JS

    instance.detect("server.cjs", content).should be_true
  end

  it "does not detect adapter-only createServer usage" do
    content = <<-TS
      import { createYoga } from 'graphql-yoga';
      import { createServer } from 'node:http';

      const yoga = createYoga({ schema });
      createServer(yoga).listen(4000);
      TS

    instance.detect("server.ts", content).should be_false
  end

  it "does not detect outbound http client usage" do
    content = <<-JS
      const http = require('http');
      http.get('http://example.com/users', res => {});
      JS

    instance.detect("client.js", content).should be_false
  end

  it "does not detect package json without source signal" do
    instance.detect("package.json", %({"type":"module","engines":{"node":">=20"}})).should be_false
  end
end
