require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Next.js" do
  options = create_test_options
  instance = Detector::Javascript::Nextjs.new options

  it "next_config_js" do
    instance.detect("next.config.js", "module.exports = {}").should be_true
  end

  it "next_config_ts" do
    instance.detect("next.config.ts", "export default {}").should be_true
  end

  it "next_config_mjs" do
    instance.detect("next.config.mjs", "export default {}").should be_true
  end

  it "package_json_with_next" do
    content = %({"dependencies": {"next": "14.2.0", "react": "18.3.0"}})
    instance.detect("package.json", content).should be_true
  end

  it "package_json_without_next" do
    content = %({"dependencies": {"react": "18.3.0"}})
    instance.detect("package.json", content).should be_false
  end

  it "pages_api_ts" do
    instance.detect("project/pages/api/users.ts", "export default function handler() {}").should be_true
  end

  it "pages_api_js" do
    instance.detect("project/pages/api/users.js", "module.exports = {}").should be_true
  end

  it "pages_api_dynamic" do
    instance.detect("project/pages/api/users/[id].ts", "export default function() {}").should be_true
  end

  it "app_route_ts" do
    instance.detect("project/app/api/products/route.ts", "export async function GET() {}").should be_true
  end

  it "app_route_js" do
    instance.detect("project/app/api/products/route.js", "export async function GET() {}").should be_true
  end

  it "app_route_with_dynamic" do
    instance.detect("project/app/api/products/[id]/route.ts", "export async function GET() {}").should be_true
  end

  it "import_from_next" do
    instance.detect("index.ts", "import Link from 'next/link'").should be_true
  end

  it "import_from_next_server" do
    instance.detect("index.ts", %(import { NextRequest } from "next/server")).should be_true
  end

  it "import_from_next_headers" do
    instance.detect("index.ts", %(import { cookies } from "next/headers")).should be_true
  end

  it "require_next" do
    instance.detect("index.js", "const next = require('next')").should be_true
  end

  it "not_detect_random_ts" do
    instance.detect("random.ts", "const x = 1").should be_false
  end

  it "not_detect_non_js_file" do
    instance.detect("index.py", "import next").should be_false
  end
end
