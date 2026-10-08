require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Deno.serve" do
  options = create_test_options
  instance = Detector::Javascript::Deno.new options

  it "detects Deno.serve with URLPattern routing" do
    content = <<-TS
      const BOOK_ROUTE = new URLPattern({ pathname: "/books/:id" });
      Deno.serve((req) => {
        const match = BOOK_ROUTE.exec(req.url);
        return new Response(match ? "book" : "missing");
      });
      TS

    instance.detect("main.ts", content).should be_true
  end

  it "detects Deno.serve branching on method" do
    content = <<-TS
      Deno.serve({ port: 8000 }, (req) => {
        if (req.method === "POST") return new Response("created");
        return new Response("ok");
      });
      TS

    instance.detect("main.ts", content).should be_true
  end

  it "does not detect Deno.serve hosting a framework app" do
    content = <<-TS
      import { Hono } from "jsr:@hono/hono";
      const app = new Hono();
      Deno.serve(app.fetch);
      TS

    instance.detect("main.ts", content).should be_false
  end
end
