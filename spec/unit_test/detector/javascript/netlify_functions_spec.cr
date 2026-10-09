require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Netlify Functions" do
  options = create_test_options
  instance = Detector::Javascript::NetlifyFunctions.new options

  it "modern default export in netlify/functions" do
    content = %(export default async (req: Request) => new Response("Hello");\nexport const config: Config = { path: "/api/hello" };)
    instance.detect("netlify/functions/hello.mts", content).should be_true
    instance.detect("site/netlify/functions/users/index.ts", content).should be_true
  end

  it "legacy handler and edge functions" do
    instance.detect("netlify/functions/legacy.js", %(exports.handler = async (event) => ({ statusCode: 200 });)).should be_true
    instance.detect("netlify/edge-functions/geo.ts", %(export default async (request) => new Response("x");)).should be_true
  end

  it "functions directory configured in netlify.toml" do
    instance.detect("netlify.toml", %([functions]\n  directory = "src/lambdas"\n)).should be_true
    instance.detect("netlify.toml", %([build]\n  publish = "dist"\n  functions = "functions"\n)).should be_true
  end

  it "ignores netlify.toml without a functions directory" do
    instance.detect("netlify.toml", %([build]\n  publish = "dist"\n\n[[redirects]]\n  from = "/old"\n  to = "/new"\n)).should be_false
  end

  it "ignores helpers, nested modules and files outside netlify/functions" do
    instance.detect("netlify/functions/users/helpers.ts", %(export default function helper() {})).should be_false
    instance.detect("netlify/functions/lib/deep/x.ts", %(export default function x() {})).should be_false
    instance.detect("netlify/functions/types.ts", %(export type Foo = string;)).should be_false
    instance.detect("functions/hello.ts", %(export default async () => new Response("x");)).should be_false
  end
end
