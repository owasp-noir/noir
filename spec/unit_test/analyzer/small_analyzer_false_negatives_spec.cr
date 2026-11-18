require "file_utils"
require "../../spec_helper"
require "../../../src/models/noir"

# Runs the full detect + analyze pipeline on an invented project and returns
# "METHOD url" => sorted "name:type" params, so a spec can pin the params a
# route carries, not only that the route exists.
private def scan_files(files : Hash(String, String)) : Hash(String, Array(String))
  dir = File.tempname("small_fn_spec")
  Dir.mkdir_p(dir)
  files.each do |name, content|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.to_h do |ep|
    {"#{ep.method} #{ep.url}", ep.params.map { |p| "#{p.name}:#{p.param_type}" }.sort!}
  end
ensure
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(dir) if dir
end

describe "js_http path-only dispatch" do
  it "detects a createServer that branches on the pathname without reading req.method" do
    routes = scan_files({
      "server.js" => <<-JS,
        const http = require("node:http");
        http.createServer((req, res) => {
          const u = new URL(req.url, "http://localhost");
          if (u.pathname === "/status") return res.end("ok");
          if (u.pathname === "/items") return res.end("[]");
          res.statusCode = 404;
          res.end();
        }).listen(8080);
        JS
    })
    routes.keys.sort!.should eq(["GET /items", "GET /status"])
  end

  it "scopes params to the brace-less branch that reads them" do
    routes = scan_files({
      "server.js" => <<-JS,
        const http = require("node:http");
        http.createServer((req, res) => {
          const u = new URL(req.url, "http://localhost");
          if (req.method === "HEAD") return res.end();
          if (u.pathname === "/status") return res.end("ok");
          if (u.pathname === "/search") return res.end(u.searchParams.get("q") || "");
          if (u.pathname === "/page") {
            return res.end(u.searchParams.get("n"));
          }
          res.end();
        }).listen(8080);
        JS
    })
    routes["GET /status"].should eq([] of String)
    routes["GET /search"].should eq(["q:query"])
    routes["GET /page"].should eq(["n:query"])
  end

  it "keeps a path block's params for a verb test written as one statement" do
    routes = scan_files({
      "server.js" => <<-JS,
        const http = require("node:http");
        http.createServer((req, res) => {
          const u = new URL(req.url, "http://localhost");
          if (u.pathname === "/items") {
            const q = u.searchParams.get("q");
            if (req.method === "GET") return list(res, q);
            if (req.method === "POST") return create(res);
          }
          res.end();
        }).listen(8080);
        JS
    })
    routes["GET /items"].should eq(["q:query"])
    routes["POST /items"].should eq(["q:query"])
  end

  it "keeps params read above one-statement guards and drops the other branches' reads" do
    routes = scan_files({
      "server.js" => <<-JS,
        const http = require("node:http");
        http.createServer((req, res) => {
          const u = new URL(req.url, "http://localhost");
          const id = u.searchParams.get("id");
          const token = req.headers["x-demo-token"];
          if (req.method === "GET" && u.pathname === "/items") return list(res, id, token, u.searchParams.get("sort"));
          if (u.pathname === "/status") return res.end(u.searchParams.get("verbose"));
          res.end();
        }).listen(8080);
        JS
    })
    routes["GET /items"].should eq(["id:query", "sort:query", "x-demo-token:header"])
    routes["GET /status"].should eq(["id:query", "verbose:query", "x-demo-token:header"])
  end

  it "keeps params read above a one-statement path test nested in a method block" do
    routes = scan_files({
      "server.js" => <<-JS,
        const http = require("node:http");
        http.createServer((req, res) => {
          const u = new URL(req.url, "http://localhost");
          const id = u.searchParams.get("id");
          if (req.method === "GET") {
            if (u.pathname === "/status") return res.end("ok");
          }
          res.end();
        }).listen(8080);
        JS
    })
    routes["GET /status"].should eq(["id:query"])
  end
end

describe "express routes declared on a resolved constant path" do
  it "keeps the handler params of a template-literal or concatenated path" do
    routes = scan_files({
      "app.js" => <<-JS,
        const express = require('express')
        const BASE = '/base'
        const app = express()
        app.get(`${BASE}/a`, (req, res) => { res.send(req.header('x-a') + req.query.q) })
        app.get(BASE + '/b', (req, res) => { res.send(req.header('x-b') + req.query.q) })
        app.get('/c', (req, res) => { res.send(req.header('x-c') + req.query.q) })
        JS
    })
    routes["GET /base/a"].should eq(["q:query", "x-a:header"])
    routes["GET /base/b"].should eq(["q:query", "x-b:header"])
    routes["GET /c"].should eq(["q:query", "x-c:header"])
  end
end

describe "rust clap derive fields" do
  cargo = %([package]\nname = "demo"\nversion = "0.1.0"\n\n[dependencies]\nclap = { version = "4", features = ["derive"] }\n)

  it "reads #[arg] flags on pub(crate) and pub(super) fields" do
    routes = scan_files({
      "Cargo.toml"  => cargo,
      "src/main.rs" => <<-RS,
        use clap::{Parser, Subcommand};

        #[derive(Parser)]
        struct Cli {
            #[arg(long)]
            pub(crate) dry_run: bool,
            #[arg(long)]
            pub(super) output: Option<String>,
            #[arg(long)]
            pub quiet: bool,
            #[command(subcommand)]
            pub command: Commands,
        }

        #[derive(Subcommand)]
        enum Commands {
            Run,
        }

        fn main() {
            let _ = Cli::parse();
        }
        RS
    })
    routes["CLI cli://demo"].should eq(["dry-run:flag", "output:flag", "quiet:flag"])
  end

  it "emits an unattributed field of an Args struct as a positional" do
    routes = scan_files({
      "Cargo.toml"  => cargo,
      "src/main.rs" => <<-RS,
        use clap::{Args, Parser, Subcommand};

        #[derive(Parser)]
        struct Cli {
            #[command(subcommand)]
            command: Commands,
        }

        #[derive(Subcommand)]
        enum Commands {
            Show(ShowArgs),
            Build(BuildArgs),
        }

        #[derive(Args)]
        pub struct ShowArgs {
            /// Item path
            pub item_path: Option<String>,
        }

        #[derive(Args)]
        pub struct BuildArgs {
            #[arg(long)]
            pub release: bool,
            pub bare_input: String,
            #[arg(skip)]
            pub cache: String,
            #[command(flatten)]
            pub extra: ExtraArgs,
            #[clap(flatten)]
            pub legacy: ExtraArgs,
        }

        #[derive(Args)]
        pub struct ExtraArgs {
            #[arg(long)]
            pub jobs: u32,
        }

        fn main() {
            let _ = Cli::parse();
        }
        RS
    })
    routes["CLI cli://demo/show"].should eq(["item-path:argument"])
    routes["CLI cli://demo/build"].should contain("bare-input:argument")
    routes["CLI cli://demo/build"].should contain("release:flag")
    routes["CLI cli://demo/build"].should_not contain("cache:argument")
    routes["CLI cli://demo/build"].should_not contain("extra:argument")
    routes["CLI cli://demo/build"].should_not contain("legacy:argument")
  end
end

describe "python argparse subcommand without arguments" do
  it "emits an add_parser subcommand that has no add_argument, assigned or not" do
    routes = scan_files({
      "tool.py" => <<-PY,
        import argparse

        def main():
            ap = argparse.ArgumentParser(prog="demo")
            sub = ap.add_subparsers(dest="cmd", required=True)
            f = sub.add_parser("run")
            f.add_argument("item_id")
            g = sub.add_parser("status")
            sub.add_parser("reset", help="no args")
            ap.parse_args()

        if __name__ == "__main__":
            main()
        PY
    })
    routes.keys.sort!.should eq(["CLI cli://demo/reset", "CLI cli://demo/run", "CLI cli://demo/status"])
    routes["CLI cli://demo/run"].should eq(["item_id:argument"])
  end
end

describe "python http.server do_GET branches" do
  it "reads each branch's params for its own path only" do
    routes = scan_files({
      "server.py" => <<-PY,
        from http.server import BaseHTTPRequestHandler
        from urllib.parse import urlparse, parse_qs

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                url = urlparse(self.path)
                if url.path == "/a":
                    self.send_response(200)
                elif url.path == "/b":
                    n = parse_qs(url.query)["n"]
                    self.send_response(200)
                else:
                    self.send_response(404)
        PY
    })
    routes["GET /a"].should eq([] of String)
    routes["GET /b"].should eq(["n:query"])
  end
end

describe "nuxt config forwards" do
  it "reports a Nitro routeRules proxy and skips redirect-only rules" do
    routes = scan_files({
      "package.json"   => %({"dependencies":{"nuxt":"^3.10.0"}}),
      "nuxt.config.ts" => <<-TS,
        export default defineNuxtConfig({
          routeRules: { '/old': { redirect: '/new' } },
          nitro: {
            routeRules: {
              '/api/**': { proxy: `${process.env.API_BASE}/api/**` },
              '/static/**': { headers: { 'cache-control': 'max-age=60' } },
            },
          },
        })
        TS
    })
    routes.keys.should eq(["ANY /api/**"])
  end

  it "reports a Nuxt 2 @nuxtjs/proxy context and a serverMiddleware path" do
    routes = scan_files({
      "package.json"   => %({"dependencies":{"nuxt":"^2.15.8","@nuxtjs/proxy":"^2.1.0"}}),
      "nuxt.config.js" => <<-JS,
        export default {
          modules: ['@nuxtjs/axios', '@nuxtjs/proxy'],
          serverMiddleware: [{ path: '/hook', handler: '~/server-middleware/hook.js' }, '~/server-middleware/logger.js'],
          proxy: [['/api/', { target: 'http://backend.example/api/v1/', ws: true }]],
        }
        JS
    })
    routes.keys.sort!.should eq(["ANY /api/**", "ANY /hook"])
  end

  it "does not read a dev-server proxy nested in the vite config" do
    routes = scan_files({
      "package.json"   => %({"dependencies":{"nuxt":"^2.15.8","@nuxtjs/proxy":"^2.1.0"}}),
      "nuxt.config.js" => <<-JS,
        export default {
          modules: ['@nuxtjs/proxy'],
          vite: { server: { proxy: { '/dev': { target: 'http://backend.example' } } } },
          proxy: { '/api/': 'http://backend.example' },
        }
        JS
    })
    routes.keys.should eq(["ANY /api/**"])
  end

  it "ignores a proxy key when the proxy module is not installed" do
    routes = scan_files({
      "package.json"   => %({"dependencies":{"nuxt":"^2.15.8"}}),
      "nuxt.config.js" => <<-JS,
        export default {
          axios: { proxy: { host: 'proxy.example', port: 3128 } },
        }
        JS
    })
    routes.should be_empty
  end
end
