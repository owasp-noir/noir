require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/remix"

describe "Detect JS Remix" do
  options = create_test_options
  instance = Detector::Javascript::Remix.new options

  it "detects package.json with Remix v2 packages" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"dependencies": {"@remix-run/node": "^2.0.0", "@remix-run/react": "^2.0.0"}})).should be_true
  end

  it "detects remix.config.* and the Remix vite plugin" do
    instance.detect("remix.config.js", "module.exports = {};").should be_true
    instance.detect("vite.config.ts", %(import { vitePlugin as remix } from "@remix-run/dev";)).should be_true
  end

  it "detects route modules importing Remix runtimes" do
    instance.detect("app/routes/_index.tsx", %(import { json } from "@remix-run/cloudflare";)).should be_true
    instance.detect("app/routes/_index.tsx", %(import type { LoaderFunctionArgs } from "@remix-run/node";)).should be_true
  end

  # React Router v7 and Remix 3 publish utilities under the same scope.
  it "does not detect other packages in the @remix-run scope" do
    instance.detect("package.json", %({"dependencies": {"@remix-run/node-fetch-server": "0.13.0", "@react-router/serve": "*"}})).should be_false
    instance.detect("package.json", %({"dependencies": {"@remix-run/router": "^1.0.0", "react-router-dom": "^6.0.0"}})).should be_false
    instance.detect("server.ts", %(import { createRequestListener } from "@remix-run/node-fetch-server";)).should be_false
  end
end
