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
    get = extractor.exported_handler(content, "onRequestGet").not_nil!
    {get.params, get.line, get.body_line}.should eq({"ctx", 1, 1})
    get.body.should contain("ctx.params.id")

    post = extractor.exported_handler(content, "onRequestPost").not_nil!
    {post.params, post.line}.should eq({"{ request }", 4})
    extractor.exported_handler(content, "handler").not_nil!.params.should eq "event"
    extractor.exported_handler(content, "onRequestDelete").not_nil!.params.should eq "context"
    extractor.exported_handler(content, "onRequestPut").should be_nil
  end

  it "resolves default exports, Fetchable objects and wrapped handlers" do
    extractor.default_handler(%(export default async (req: Request) => new Response("x");)).not_nil!.params.should eq "req: Request"
    extractor.default_handler(%(module.exports = function (req, res) { res.end(); };)).not_nil!.params.should eq "req, res"

    fetchable = extractor.default_handler(%(export default {\n  async fetch(req) {\n    return new Response(req.url);\n  },\n};)).not_nil!
    {fetchable.params, fetchable.body_line}.should eq({"req", 2})

    wrapped = extractor.default_handler(%(const handler = (req, res) => res.end();\nexport default withAuth(handler);)).not_nil!
    wrapped.params.should eq "req, res"
    extractor.default_handler(%(export const config = {};)).should be_nil
  end

  # Every `(` in a wrapper's arguments is probed for an arrow; on a
  # non-ASCII file each probe used to copy the whole source to a char array.
  it "finds a wrapped arrow after many calls in a non-ASCII file quickly" do
    calls = (1..8000).join(", ") { |i| "f(#{i})" }
    content = "// 한국어\nexport const onRequest = wrap(#{calls}, async (ctx) => { return ctx.request.method; });\n"
    handler = nil
    elapsed = Time.measure { handler = extractor.exported_handler(content, "onRequest") }
    handler.not_nil!.params.should eq "ctx"
    handler.not_nil!.body.should contain "ctx.request.method"
    elapsed.should be < 2.seconds
  end

  it "reads config strings only from the module's config" do
    content = %(export default async () => new Response();\nexport const config: Config = {\n  path: ["/api/a/:id", "/api/b"],\n  method: "GET",\n};)
    config = extractor.config_object(content).not_nil!
    extractor.config_strings(config, "path").should eq ["/api/a/:id", "/api/b"]
    extractor.config_strings(config, "method").should eq ["GET"]
    extractor.config_key?(config, "schedule").should be_false

    fetchable = %(export default {\n  fetch(req) { return new Response(); },\n  config: { path: "/f" },\n};)
    extractor.config_strings(extractor.config_object(fetchable).not_nil!, "path").should eq ["/f"]
    extractor.config_object(%(export default async () => client({ config: { path: "/x" } });)).should be_nil
  end

  it "infers the methods a handler branches on" do
    body = %(if (req.method === "POST") {}\nswitch (request.method) { case "PUT": break; case 'delete': break; }\nif (["GET", "HEAD"].includes(req.method)) {}\nif (event.httpMethod !== "PATCH") {})
    extractor.inferred_methods(body).should eq ["POST", "PATCH", "GET", "HEAD", "PUT", "DELETE"]
    extractor.inferred_methods("return new Response();").should be_empty
  end

  it "extracts request params for each handler style" do
    context = extractor.exported_handler(%(export const onRequest = async ({ request, params }) => {\n  const t = request.headers.get("x-token");\n  const { name } = await request.json();\n};), "onRequest").not_nil!
    endpoint = Endpoint.new("/a", "GET")
    extractor.extract_request_params(context, endpoint, :context)
    endpoint.params.map { |p| {p.name, p.param_type} }.should eq [{"x-token", "header"}, {"name", "json"}]

    lambda = extractor.exported_handler(%(exports.handler = async (event) => {\n  const { page } = event.queryStringParameters;\n  const q = event.queryStringParameters.q;\n};), "handler").not_nil!
    endpoint = Endpoint.new("/b", "GET")
    extractor.extract_request_params(lambda, endpoint, :lambda)
    endpoint.params.map { |p| {p.name, p.param_type} }.should eq [{"page", "query"}, {"q", "query"}]
  end
end
