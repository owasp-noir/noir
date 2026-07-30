require "../../spec_helper"
require "../../../src/models/noir"
require "../../../src/miniparsers/js_route_extractor"
require "file_utils"

private def scan_tree(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.clear("file_map")
end

private def tech_sources(endpoints : Array(Endpoint), technology : String) : Array(String)
  endpoints.compact_map do |endpoint|
    next unless endpoint.details.technology == technology
    endpoint.details.code_paths.first?.try(&.path)
  end.uniq!
end

describe Noir::JSRouteExtractor do
  describe ".other_shared_extractor_framework?" do
    it "refuses a client module that stands up no server" do
      # `client.get('/todo', cb)` is the same call shape as a route
      # registration, so a restify-clients module read as an Express server:
      # `GET /todo` and `DELETE /todo/example` out of code that only calls a
      # remote API.
      client = <<-JS
        const clients = require('restify-clients')

        const client = clients.createJSONClient({ url: 'http://localhost:8080' })

        client.get('/todo', function noop() {})
        client.del('/todo/example', function noop() {})
        JS

      Noir::JSRouteExtractor.other_shared_extractor_framework?(client, :express).should be_true
    end

    it "keeps a test that stands up a real server and then calls it" do
      # A client constructor only disqualifies a file that serves nothing of
      # its own.
      both = <<-JS
        const express = require('express')
        const clients = require('restify-clients')

        const app = express()
        app.get('/health', (req, res) => res.send('ok'))
        JS

      Noir::JSRouteExtractor.other_shared_extractor_framework?(both, :express).should be_false
    end

    it "leaves a marker-less fastify autoload plugin to fastify" do
      # `@fastify/autoload` plugin modules import nothing — the instance
      # arrives as a parameter, so the receiver name is the only evidence.
      plugin = <<-JS
        export const autoPrefix = '/_app';

        export default async function (fastify) {
          fastify.get('/status', async () => ({ status: 'ok' }));
        }
        JS

      Noir::JSRouteExtractor.other_shared_extractor_framework?(plugin, :express).should be_true
      Noir::JSRouteExtractor.other_shared_extractor_framework?(plugin, :fastify).should be_false
    end
  end
end

describe "Fresh project scoping" do
  it "keeps Fresh off another framework's routes/ directory" do
    # `routes/` is Remix's directory too (`app/routes/`), and Koa/Express
    # projects routinely have one. Fresh claimed every `*/routes/*` in the
    # scan, so Remix's `users.$id.tsx` surfaced as a Fresh endpoint named
    # after the file.
    root = File.tempname("noir-fresh-scope")

    begin
      site = File.join(root, "site")
      FileUtils.mkdir_p(File.join(site, "routes"))
      File.write(File.join(site, "deno.json"), %({"imports": {"$fresh/": "https://deno.land/x/fresh@1.6.8/"}}))
      # A real Fresh route imports from `$fresh/` — that is what the
      # detector keys on, so the synthetic project needs it too.
      File.write(File.join(site, "routes", "about.tsx"), <<-TSX)
        import { Handlers } from "$fresh/server.ts";

        export const handler: Handlers = {
          GET(_req, ctx) {
            return ctx.render();
          },
        };
        TSX

      web = File.join(root, "web", "app", "routes")
      FileUtils.mkdir_p(web)
      File.write(File.join(root, "web", "package.json"), %({"dependencies": {"@remix-run/node": "^2.0.0"}}))
      # The ordinary Remix route shape: a loader plus a default component.
      # The default export is what Fresh reads as a page, which is how these
      # modules ended up as `js_fresh` endpoints named after the file.
      File.write(File.join(web, "users.$id.tsx"), <<-TSX)
        import type { LoaderFunctionArgs } from "@remix-run/node";

        export async function loader({ params }: LoaderFunctionArgs) {
          return { id: params.id };
        }

        export default function User() {
          return <h1>user</h1>;
        }
        TSX

      endpoints = scan_tree(root)
      fresh_sources = tech_sources(endpoints, "js_fresh")
      fresh_sources.any?(&.includes?("/site/routes/about.tsx")).should be_true
      fresh_sources.any?(&.includes?("/web/")).should be_false
      # And nothing surfaces the Remix filename as a URL.
      endpoints.map(&.url).none?(&.includes?(".$")).should be_true
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
