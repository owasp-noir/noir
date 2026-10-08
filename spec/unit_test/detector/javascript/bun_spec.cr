require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Bun.serve" do
  options = create_test_options
  instance = Detector::Javascript::Bun.new options

  it "detects a Bun.serve route map" do
    content = <<-TS
      Bun.serve({
        routes: { "/api/status": new Response("OK") },
      });
      TS

    instance.detect("server.ts", content).should be_true
  end

  it "detects a Bun.serve fetch handler branching on pathname" do
    content = <<-JS
      Bun.serve({
        fetch(req) {
          const url = new URL(req.url);
          if (url.pathname === "/health") return new Response("ok");
        },
      });
      JS

    instance.detect("server.js", content).should be_true
  end

  it "does not detect Bun.serve hosting a framework app" do
    content = <<-TS
      import { Hono } from "hono";
      const app = new Hono();
      Bun.serve({ port: 3000, fetch: app.fetch });
      TS

    instance.detect("server.ts", content).should be_false
  end
end
