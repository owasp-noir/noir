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
  CodeLocator.instance.reset_files
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

describe "Remix and React Router project scoping" do
  it "keeps each analyzer on its own app's routes/ directory" do
    # Both frameworks read the same `app/routes/` convention, so without a
    # project root each one claimed the other's routes as its own.
    root = File.tempname("noir-remix-rr-scope")

    begin
      remix = File.join(root, "remix-app")
      FileUtils.mkdir_p(File.join(remix, "app", "routes"))
      File.write(File.join(remix, "package.json"), %({"dependencies": {"@remix-run/node": "^2.0.0"}}))
      File.write(File.join(remix, "app", "routes", "about.tsx"), "export default function About() {}\n")

      # No `app/routes.ts`: React Router falls back to the file convention.
      rr = File.join(root, "rr-app")
      FileUtils.mkdir_p(File.join(rr, "app", "routes"))
      File.write(File.join(rr, "package.json"), %({"devDependencies": {"@react-router/dev": "^7.9.0"}}))
      File.write(File.join(rr, "app", "routes", "users.$id.tsx"), <<-TSX)
        export async function loader({ params }) {
          return { id: params.id };
        }

        export default function User() {}
        TSX

      endpoints = scan_tree(root)
      tech_sources(endpoints, "js_remix").should eq([File.join(remix, "app", "routes", "about.tsx")])
      tech_sources(endpoints, "js_react_router").should eq([File.join(rr, "app", "routes", "users.$id.tsx")])
      endpoints.select { |e| e.details.technology == "js_react_router" }.map(&.url).uniq!.should eq(["/users/{id}"])
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "splits apps by route config when one root package.json hoists both" do
    # A root package.json naming both frameworks makes the repo root a project
    # root for each, so roots alone cannot tell the apps apart. The route
    # config can: every React Router app has one and no Remix app does.
    root = File.tempname("noir-remix-rr-hoisted")

    begin
      File.write(File.join(root.tap { |r| FileUtils.mkdir_p(r) }, "package.json"),
        %({"devDependencies": {"@remix-run/dev": "^2.0.0", "@react-router/dev": "^7.9.0"}}))

      remix_routes = File.join(root, "apps", "remix", "app", "routes")
      FileUtils.mkdir_p(remix_routes)
      File.write(File.join(remix_routes, "about.tsx"), "export default function About() {}\n")

      rr_app = File.join(root, "apps", "rr", "app")
      FileUtils.mkdir_p(File.join(rr_app, "routes"))
      FileUtils.mkdir_p(File.join(rr_app, "features", "admin"))
      File.write(File.join(rr_app, "routes.ts"), <<-TS)
        import { type RouteConfig, index } from "@react-router/dev/routes";
        export default [index("routes/home.tsx")] satisfies RouteConfig;
        TS
      File.write(File.join(rr_app, "routes", "home.tsx"), "export default function Home() {}\n")
      # A split-out config: its module paths are relative to the app
      # directory, not to the directory the file sits in.
      File.write(File.join(rr_app, "features", "admin", "routes.ts"), <<-TS)
        import { prefix, route } from "@react-router/dev/routes";
        export default prefix("admin", [route("users", "features/admin/users.tsx")]);
        TS
      File.write(File.join(rr_app, "features", "admin", "users.tsx"), <<-TSX)
        export async function action() {}
        export default function Users() {}
        TSX

      endpoints = scan_tree(root)
      tech_sources(endpoints, "js_remix").should eq([File.join(remix_routes, "about.tsx")])

      rr = endpoints.select { |e| e.details.technology == "js_react_router" }
      rr.map(&.url).uniq!.sort!.should eq(["/", "/admin/users"])
      rr.find! { |e| e.method == "POST" }.details.code_paths.first.path.should eq(File.join(rr_app, "features", "admin", "users.tsx"))
      # `routes/home.tsx` is the index route, never `/home`.
      endpoints.map(&.url).should_not contain("/home")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end

describe "src/routes/ framework project scoping" do
  it "keeps SvelteKit, SolidStart and Qwik City on their own apps" do
    # All three route from `src/routes/`; a default-exported `index.tsx` is
    # a page to both SolidStart and Qwik City, so ownership is the only guard.
    root = File.tempname("noir-src-routes-scope")

    begin
      kit = File.join(root, "kit", "src", "routes", "about")
      FileUtils.mkdir_p(kit)
      File.write(File.join(root, "kit", "package.json"), %({"devDependencies": {"@sveltejs/kit": "^2.0.0"}}))
      File.write(File.join(kit, "+page.svelte"), "<h1>About</h1>\n")

      solid = File.join(root, "solid", "src", "routes")
      FileUtils.mkdir_p(solid)
      File.write(File.join(root, "solid", "package.json"), %({"dependencies": {"@solidjs/start": "^1.1.0"}}))
      File.write(File.join(solid, "pricing.tsx"), "export default function Pricing() {}\n")

      qwik = File.join(root, "qwik", "src", "routes", "team")
      FileUtils.mkdir_p(qwik)
      File.write(File.join(root, "qwik", "package.json"), %({"devDependencies": {"@builder.io/qwik-city": "^1.12.0"}}))
      File.write(File.join(qwik, "index.tsx"), "export default component$(() => null);\n")

      endpoints = scan_tree(root)
      tech_sources(endpoints, "js_sveltekit").should eq([File.join(kit, "+page.svelte")])
      tech_sources(endpoints, "js_solidstart").should eq([File.join(solid, "pricing.tsx")])
      tech_sources(endpoints, "js_qwik_city").should eq([File.join(qwik, "index.tsx")])
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end

describe "src/routes/ framework hoisted package.json" do
  it "leaves a nested app with its own package.json to its framework" do
    # The root package.json names SolidStart, but `packages/kit` has its own
    # manifest: its `+server.ts` verb export is not a SolidStart route.
    root = File.tempname("noir-src-routes-hoisted")

    begin
      solid = File.join(root, "src", "routes")
      FileUtils.mkdir_p(solid)
      File.write(File.join(root, "package.json"), %({"dependencies": {"@solidjs/start": "^1.1.0"}}))
      File.write(File.join(solid, "index.tsx"), "export default function Home() {}\n")

      kit = File.join(root, "packages", "kit", "src", "routes", "api")
      FileUtils.mkdir_p(kit)
      File.write(File.join(root, "packages", "kit", "package.json"), %({"devDependencies": {"@sveltejs/kit": "^2.0.0"}}))
      File.write(File.join(kit, "+server.ts"), "export const GET = () => new Response();\n")

      endpoints = scan_tree(root)
      tech_sources(endpoints, "js_solidstart").should eq([File.join(solid, "index.tsx")])
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
