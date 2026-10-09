require "../../../spec_helper"
require "file_utils"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Vercel Functions" do
  options = create_test_options
  instance = Detector::Javascript::VercelFunctions.new options

  it "root api/ handler importing @vercel/node" do
    content = %(import type { VercelRequest, VercelResponse } from "@vercel/node";\nexport default function handler(req: VercelRequest, res: VercelResponse) { res.json({}); })
    instance.detect("api/hello.ts", content).should be_true
  end

  it "root api/ handler in a project with vercel.json" do
    dir = File.tempname("noir_vercel_functions")
    Dir.mkdir_p(File.join(dir, "api"))
    File.write(File.join(dir, "vercel.json"), "{}")
    begin
      instance.detect(File.join(dir, "api", "orders.js"), %(module.exports = (req, res) => res.end();)).should be_true
      instance.detect(File.join(dir, "api", "v2.ts"), %(export function GET(request: Request) { return new Response(); })).should be_true
      instance.detect(File.join(dir, "api", "_lib", "db.ts"), %(export default function db() {})).should be_false
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "ignores api/ without a Vercel signal" do
    instance.detect("api/hello.ts", %(export default function handler(req, res) { res.end(); })).should be_false
  end

  it "ignores Next.js pages/api, app/api and Nuxt server/api" do
    content = %(import type { VercelRequest } from "@vercel/node";\nexport default function handler(req: VercelRequest, res) { res.end(); })
    instance.detect("pages/api/hello.ts", content).should be_false
    instance.detect("src/app/api/users/route.ts", content).should be_false
    instance.detect("server/api/hello.ts", content).should be_false
  end

  it "ignores modules without a handler export and test files" do
    instance.detect("api/types.ts", %(import type { VercelRequest } from "@vercel/node";\nexport type Req = VercelRequest;)).should be_false
    instance.detect("api/hello.test.ts", %(import "@vercel/node";\nexport default function t() {})).should be_false
  end
end
