require "../../spec_helper"
require "../../../src/miniparsers/wasp_extractor"
require "../../../src/analyzer/analyzers/typescript/wasp"

describe Noir::WaspExtractor do
  it "reads DSL declarations and ignores comments and quoted PSL blocks" do
    content = <<-WASP
      app a {
        wasp: { version: "^0.16.0" },
        auth: { userEntity: User, methods: { email: {}, gitHub: {} } }
      }
      // api old { fn: import { old } from "@src/apis", httpRoute: (GET, "/old") }
      api fooBar {
        fn: import { fooBar as foo } from "@src/apis",
        httpRoute: (POST, "/foo/:id"), // trailing comment
        auth: false
      }
      entity Note {=psl
        id Int @id // api fake { httpRoute: (GET, "/psl") }
      psl=}
      query getTasks { fn: import getTasks from "@src/queries" }
      WASP
    spec = Noir::WaspExtractor.parse_dsl(content)
    spec.auth_enabled.should be_true
    spec.auth_methods.should eq ["email", "gitHub"]
    spec.apis.map { |api| {api.name, api.method, api.path, api.auth, api.fn.try(&.name), api.line} }.should eq [
      {"fooBar", "POST", "/foo/:id", false, "fooBar", 6},
    ]
    spec.operations.map { |op| {op.kind, op.name, op.fn.try(&.name), op.fn.try(&.from)} }.should eq [
      {"query", "getTasks", "default", "@src/queries"},
    ]
  end

  it "reads many declarations of a non-ASCII spec in linear time, on the right lines" do
    content = %(app a {\n  title: "한국어 앱"\n}\n) +
              (0...4000).join { |i| %(api a#{i} {\n  fn: import { a } from "@src/a",\n  httpRoute: (GET, "/한/#{i}")\n}\n) }
    spec = nil
    elapsed = Time.measure { spec = Noir::WaspExtractor.parse_dsl(content) }
    apis = spec.not_nil!.apis
    apis.size.should eq 4000
    {apis.last.path, apis.last.line}.should eq({"/한/3999", 4 + 3999 * 4})
    elapsed.should be < 2.seconds
  end

  it "does not treat apiNamespace as a route prefix" do
    content = <<-WASP
      apiNamespace bar { middlewareConfigFn: import { mw } from "@src/apis", path: "/bar" }
      api baz { fn: import { baz } from "@src/apis", httpRoute: (GET, "/baz") }
      WASP
    Noir::WaspExtractor.parse_dsl(content).apis.map(&.path).should eq ["/baz"]
  end

  it "reads Wasp Spec calls through aliases and shared page constants" do
    content = <<-TS
      import { api as waspApi, query, route, page } from "@wasp.sh/spec";
      import { a, b as renamed } from "./ops" with { type: "ref" };
      const p = page(P, { authRequired: true });
      export const spec = [
        route("R", "/r/:id", p),
        query(renamed, { auth: false }),
        waspApi("ALL", "/hook", a),
        // query(a),
        other.query(a),
      ];
      TS
    spec = Noir::WaspExtractor.parse_spec(content)
    spec.routes.map { |r| {r.name, r.path, r.auth_required} }.should eq [{"R", "/r/:id", true}]
    spec.operations.map { |op| {op.name, op.auth, op.fn.try(&.name)} }.should eq [{"renamed", false, "b"}]
    spec.apis.map { |api| {api.method, api.path} }.should eq [{"ALL", "/hook"}]
  end

  it "finds arrow, function and wrapped handlers" do
    source = <<-TS
      export const one: One<{ a: string }> = async ({ a, b: renamed, c = 1 }, ctx) => { return a; };
      export async function two(args, ctx) { return args.x + args?.y; }
      export const three = (async (input, ctx) => { const { z } = input; }) satisfies Three;
      TS
    Noir::WaspExtractor.operation_args(Noir::WaspExtractor.handler(source, "one").not_nil!).should eq ["a", "b", "c"]
    Noir::WaspExtractor.operation_args(Noir::WaspExtractor.handler(source, "two").not_nil!).should eq ["x", "y"]
    Noir::WaspExtractor.operation_args(Noir::WaspExtractor.handler(source, "three").not_nil!).should eq ["z"]
  end

  it "kebab-cases operation names the way waspc does" do
    Analyzer::Typescript::Wasp.kebab_case("createTask").should eq "create-task"
    Analyzer::Typescript::Wasp.kebab_case("getHTTPStatus").should eq "get-httpstatus"
    Analyzer::Typescript::Wasp.kebab_case("get2FACode").should eq "get2-facode"
  end
end
