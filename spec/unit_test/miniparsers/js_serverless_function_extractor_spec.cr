require "../../spec_helper"
require "../../../src/miniparsers/js_serverless_function_extractor"

describe Noir::JSServerlessFunctionExtractor do
  extractor = Noir::JSServerlessFunctionExtractor

  it "resolves named handler exports" do
    content = <<-JS
      export async function onRequestGet(ctx) {
        return new Response(ctx.params.id);
      }
      export const onRequestPost: PagesFunction<Env> = async ({ request }) => {
        return new Response(null);
      };
      exports.handler = async (event) => ({ statusCode: 200 });
      const remove = (context) => new Response(null);
      export { remove as onRequestDelete };
      JS
    get = extractor.exported_handler(content, "f.ts", "onRequestGet").not_nil!
    {get.params, get.line, get.body_line}.should eq({"ctx", 1, 1})
    get.body.should contain("ctx.params.id")

    post = extractor.exported_handler(content, "f.ts", "onRequestPost").not_nil!
    {post.params, post.line}.should eq({"{ request }", 4})
    extractor.exported_handler(content, "f.ts", "handler").not_nil!.params.should eq "event"
    extractor.exported_handler(content, "f.ts", "onRequestDelete").not_nil!.params.should eq "context"
    extractor.exported_handler(content, "f.ts", "onRequestPut").should be_nil
  end

  it "resolves default exports, Fetchable objects and wrapped handlers" do
    extractor.default_handler(%(export default async (req: Request) => new Response("x");), "f.ts").not_nil!.params.should eq "req: Request"
    extractor.default_handler(%(module.exports = function (req, res) { res.end(); };), "f.ts").not_nil!.params.should eq "req, res"

    fetchable = extractor.default_handler(%(export default {\n  async fetch(req) {\n    return new Response(req.url);\n  },\n};), "f.ts").not_nil!
    {fetchable.params, fetchable.body_line}.should eq({"req", 2})

    wrapped = extractor.default_handler(%(const handler = (req, res) => res.end();\nexport default withAuth(handler);), "f.ts").not_nil!
    wrapped.params.should eq "req, res"
    extractor.default_handler(%(export const config = {};), "f.ts").should be_nil
  end

  # Every `(` in a wrapper's arguments is probed for an arrow; on a
  # non-ASCII file each probe used to copy the whole source to a char array.
  it "finds a wrapped arrow after many calls in a non-ASCII file quickly" do
    calls = (1..8000).join(", ") { |i| "f(#{i})" }
    content = "// 한국어\nexport const onRequest = wrap(#{calls}, async (ctx) => { return ctx.request.method; });\n"
    handler = nil
    elapsed = Time.measure { handler = extractor.exported_handler(content, "f.ts", "onRequest") }
    handler.not_nil!.params.should eq "ctx"
    handler.not_nil!.body.should contain "ctx.request.method"
    elapsed.should be < 2.seconds
  end

  it "reads config strings only from the module's config" do
    content = %(export default async () => new Response();\nexport const config: Config = {\n  path: ["/api/a/:id", "/api/b"],\n  method: "GET",\n};)
    config = extractor.config_object(content, "f.ts").not_nil!
    extractor.config_strings(config, "path").should eq ["/api/a/:id", "/api/b"]
    extractor.config_strings(config, "method").should eq ["GET"]
    extractor.config_key?(config, "schedule").should be_false

    fetchable = %(export default {\n  fetch(req) { return new Response(); },\n  config: { path: "/f" },\n};)
    extractor.config_strings(extractor.config_object(fetchable, "f.ts").not_nil!, "path").should eq ["/f"]
    extractor.config_object(%(export default async () => client({ config: { path: "/x" } });), "f.ts").should be_nil
  end

  it "reads config values off the object, not the text around it" do
    content = %(export const config = {\n  "path": ['/a', `/b`, dynamic, "/c"],\n  runtime: "edge",\n  method: METHOD,\n  nested: { path: "/no" },\n};)
    config = extractor.config_object(content, "f.ts").not_nil!
    extractor.config_strings(config, "path").should eq ["/a", "/b", "/c"]
    extractor.config_strings(config, "runtime").should eq ["edge"]
    extractor.config_strings(config, "method").should be_empty
    extractor.config_key?(config, "method").should be_true
    extractor.config_key?(config, "schedule").should be_false
  end

  it "infers the methods a handler branches on" do
    inferred = ->(body : String) { extractor.default_handler("export default async (req, event) => {\n#{body}\n};", "f.ts").not_nil!.methods }
    inferred.call(%(if (req.method === "POST") {}\nswitch (request.method) { case "PUT": break; case 'delete': break; }\nif (["GET", "HEAD"].includes(req.method)) {}\nif (event.httpMethod !== "PATCH") {})).should eq ["POST", "PATCH", "GET", "HEAD", "PUT", "DELETE"]
    inferred.call("return new Response();").should be_empty
    # aliases of the request method, and literals that only look like checks
    inferred.call(%(const { method } = req;\nif (method === "PUT") {}\nswitch (method) { case "DELETE": break; })).should eq ["PUT", "DELETE"]
    inferred.call(%(const verb = req.method;\nif ("POST" == verb) {})).should eq ["POST"]
    inferred.call(%(const s = 'req.method === "POST"'; const t = `switch (req.method) { case "PUT": }`; // req.method === "GET"\nfoo.method === "PATCH";)).should eq ["PATCH"]
    inferred.call(%(if (other === "POST") {} switch (req.method) { default: x = { a: "GET" }; })).should be_empty
  end

  it "extracts request params for each handler style" do
    context = extractor.exported_handler(%(export const onRequest = async ({ request, params }) => {\n  const t = request.headers.get("x-token");\n  const { name } = await request.json();\n};), "f.ts", "onRequest").not_nil!
    endpoint = Endpoint.new("/a", "GET")
    extractor.extract_request_params(context, endpoint, :context)
    endpoint.params.map { |p| {p.name, p.param_type} }.should eq [{"x-token", "header"}, {"name", "json"}]

    lambda = extractor.exported_handler(%(exports.handler = async (event) => {\n  const { page } = event.queryStringParameters;\n  const q = event.queryStringParameters.q;\n};), "f.ts", "handler").not_nil!
    endpoint = Endpoint.new("/b", "GET")
    extractor.extract_request_params(lambda, endpoint, :lambda)
    endpoint.params.map { |p| {p.name, p.param_type} }.should eq [{"page", "query"}, {"q", "query"}]
  end
end
