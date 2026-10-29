require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Medusa" do
  options = create_test_options
  instance = Detector::Javascript::Medusa.new options

  it "detects @medusajs/medusa or @medusajs/framework in dependencies" do
    instance.detect("package.json", %({"dependencies": {"@medusajs/medusa": "2.8.0"}})).should be_true
    instance.detect("package.json", %({"dependencies": {"@medusajs/framework": "2.8.0"}})).should be_true
    instance.detect("package.json", %({"peerDependencies": {"@medusajs/medusa": "2.8.0"}})).should be_true
  end

  it "ignores a dev-only dependency and packages that only share the prefix" do
    instance.detect("package.json", %({"dependencies": {"express": "4.0.0"}, "devDependencies": {"@medusajs/medusa": "2.8.0"}})).should be_false
    instance.detect("package.json", %({"dependencies": {"@medusajs/js-sdk": "2.8.0", "@medusajs/framework-utils": "2.8.0"}})).should be_false
    instance.detect("package.json", %({"name": "x", "dependencies": {)).should be_false
  end

  it "does not detect a random TypeScript file" do
    source = <<-TS
      import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http"
      export const GET = async (req: MedusaRequest, res: MedusaResponse) => {
        res.json({ id: req.params.id })
      }
      TS
    instance.detect("src/api/store/hello/route.ts", source).should be_false
    instance.detect("app.ts", %(import { defineMiddlewares } from "@medusajs/framework/http")).should be_false
  end
end
