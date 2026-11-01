require "../../spec_helper"
require "../../../src/miniparsers/js_handler_table"

describe Noir::JSHandlerTable do
  table = ->(source : String, path : String) { Noir::JSHandlerTable.for(source, path) }

  it "ends a body at its own brace despite braces in types, templates and regexes" do
    source = <<-TS
      export async function GET(req: Req): Promise<{ ok: true; rows: { id: number }[] }> {
        const s = `a${ { b: 1 }.b }c${ "}" }`;
        return /}{/.test(s) ? 1 : 2;
      }
      export const POST = async (req: Req): Promise<{ saved: boolean }> => {
        return { saved: true };
      };
      TS
    t = table.call(source, "r.ts")
    t.exports["GET"].body.should contain "return /}{/.test(s)"
    t.exports["GET"].body.should_not contain "export const POST"
    {t.exports["GET"].params, t.exports["GET"].body_line}.should eq({"req: Req", 1})
    t.exports["POST"].body.strip.should eq "return { saved: true };"
    t.exports["POST"].block.should be_true
  end

  it "reads expression bodies, satisfies, overloads and aliases" do
    source = <<-TS
      export const ID = async () =>
        (await cookies()).get("id");
      function real(x: string): { a: 1 } { return { a: 1 }; }
      export function OVER(a: string): void;
      export function OVER(a: number): void;
      export function OVER(a: string | number): void { work(a); }
      export const SAT = (async (r: Req) => { go(r); }) satisfies H;
      export { real as ALIASED };
      TS
    t = table.call(source, "r.ts")
    t.exports["ID"].block.should be_false
    t.exports["ID"].body.should contain "cookies()"
    t.exports["OVER"].body.should contain "work(a)"
    t.exports["SAT"].params.should eq "r: Req"
    t.exports["ALIASED"].body.should contain "return { a: 1 }"
    t.locals["real"].line.should eq 3
  end

  it "marks wrapped handlers as indirect and keeps unresolved ones empty" do
    source = <<-TS
      const inner = async (req) => { read(req); };
      export const A = withAuth(inner);
      export const B = withAuth(async (req) => { other(req); });
      export const C = missing;
      export default class Nope {}
      TS
    t = table.call(source, "r.ts")
    t.exports["A"].direct.should be_false
    t.exports["A"].body.should contain "read(req)"
    t.exports["B"].direct.should be_false
    t.exports["C"].body.should be_empty
    t.default.should be_nil
  end

  it "reads default exports, fetchable objects, CommonJS and config" do
    t = table.call("export default { async fetch(req) { return go(req); }, config: { path: \"/f\" } };", "r.ts")
    t.default.not_nil!.body.should contain "go(req)"
    t.config.not_nil!.should contain "/f"

    t = table.call("exports.handler = async (event) => { return 1; };\nmodule.exports = function (a, b) { return 2; };", "r.js")
    t.exports["handler"].params.should eq "event"
    t.default.not_nil!.params.should eq "a, b"

    table.call("export const config: Config = { path: \"/x\" } satisfies C;\nexport default async () => {};", "r.ts").config.not_nil!.should contain "/x"
  end

  it "reads handler objects by member" do
    source = "export const handler: Handlers<{ x: number }> = {\n  async GET(r): Promise<Response> { a(); },\n  POST: async (r) => { b(); },\n  PUT: 5,\n};"
    members = table.call(source, "r.ts").objects["handler"]
    members["GET"].not_nil!.body.should contain "a()"
    members["POST"].not_nil!.body.should contain "b()"
    members.has_key?("PUT").should be_true
    members["PUT"].should be_nil
  end

  it "survives deep nesting and non-ASCII source" do
    deep = "export const D = " + "(" * 500 + "async () => { go(); }" + ")" * 500 + ";\n"
    table.call("// 한국어\n" + deep, "r.ts")
    table.call("export function GET() { return 한국어; }", "r.ts").exports["GET"].body.should contain "한국어"
    table.call("export function (", "r.ts").exports.should be_empty
  end
end
