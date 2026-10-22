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
    content = "import type { NextApiRequest, NextApiResponse } from \"next\"\nexport default function handler() {}"
    instance.detect("project/pages/api/users.ts", content).should be_true
  end

  it "pages_api_js" do
    content = "const next = require('next')\nmodule.exports = {}"
    instance.detect("project/pages/api/users.js", content).should be_true
  end

  it "pages_api_dynamic" do
    content = "import { NextRequest } from \"next/server\"\nexport default function() {}"
    instance.detect("project/pages/api/users/[id].ts", content).should be_true
  end

  it "pages_api_without_next_signal" do
    # Path looks like Next.js Pages Router but the file imports nothing
    # Next.js-specific — this is the Astro / SvelteKit case where the
    # filesystem layout overlaps. Should not match.
    instance.detect("project/pages/api/users.ts", "export default function handler() {}").should be_false
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

  it "app_route_with_next_types_only" do
    # No verb export in this file (the handlers are re-exported elsewhere),
    # but it speaks to the Next.js request/response types.
    instance.detect("project/app/api/products/route.ts", %(import { NextResponse } from "next/server")).should be_true
  end

  it "app_route_destructured_handler_export" do
    instance.detect("project/app/api/workflows/route.ts", "export const { POST } = serve(async () => {});").should be_true
  end

  it "app_route_without_next_signal" do
    # `route.ts` under an `app/` directory, but nothing in the file says
    # Next.js — no verb export and no `Next*` type. The App Router branch
    # used to accept this on the path alone.
    instance.detect("project/src/app/admin/route.ts", "export const route = { path: \"/admin\" };").should be_false
  end

  # `app` is an ordinary directory name — the project's own documented
  # Docker command mounts the repo at `-w /app` — so the App Router branch
  # has to match the scan-base-relative path, not the raw one.
  it "scopes the app router directory to the scan base" do
    locator = CodeLocator.instance
    previous_bases = locator.scan_base_paths

    begin
      locator.scan_base_paths = ["/srv/myproj"]
      instance.detect("/srv/myproj/app/api/products/route.ts", "export async function GET() {}").should be_true

      locator.scan_base_paths = ["/app/myproj"]
      instance.detect("/app/myproj/server/route.ts", "export async function GET() {}").should be_false
    ensure
      locator.scan_base_paths = previous_bases
    end
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
