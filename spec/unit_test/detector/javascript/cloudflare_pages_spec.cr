require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Cloudflare Pages Functions" do
  options = create_test_options
  instance = Detector::Javascript::CloudflarePages.new options

  it "verb export under the root functions/ dir" do
    content = %(export const onRequestGet: PagesFunction = async (ctx) => new Response(ctx.params.id as string);)
    instance.detect("functions/api/users/[id].ts", content).should be_true
  end

  it "catch-all onRequest function and export clause" do
    instance.detect("functions/index.js", %(export async function onRequest(context) { return new Response("ok"); })).should be_true
    instance.detect("functions/api/ping.ts", %(const onRequestPost = () => new Response();\nexport { onRequestPost };)).should be_true
  end

  it "counts middleware as a Pages signal" do
    instance.detect("functions/_middleware.ts", %(export const onRequest = [auth, log];)).should be_true
  end

  it "ignores declarations and modules without a handler export" do
    instance.detect("functions/api/env.d.ts", %(export const onRequest = 1;)).should be_false
    instance.detect("functions/api/_lib/db.ts", %(export function query(sql) { return sql; })).should be_false
  end

  it "ignores Firebase onRequest triggers and functions/ dirs outside a project root" do
    content = %(import { onRequest } from "firebase-functions/v2/https";\nexport const onRequest = onRequest((req, res) => res.send("hi"));)
    instance.detect("functions/src/index.ts", content).should be_false
    instance.detect("src/functions/handler.ts", %(export const onRequest = () => new Response("x");)).should be_false
    instance.detect("netlify/functions/hello.ts", %(export default async () => new Response("x");)).should be_false
  end
end
