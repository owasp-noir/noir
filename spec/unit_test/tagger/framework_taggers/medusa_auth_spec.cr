require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "MedusaAuthTagger" do
  # The Medusa router authenticates every `/admin` and `/rbac` route, and
  # the `/store/customers/me` routes, unless the route file exports
  # `AUTHENTICATE = false`. Other `/store` routes only read an optional
  # customer.
  it "tags the default-protected prefixes and honors the AUTHENTICATE opt-out" do
    tmpdir = File.tempname("medusa_auth_defaults")
    routes = {
      "/admin/items"           => "export const GET = async (req, res) => {\n  res.json({})\n}\n",
      "/admin/public-info"     => "export const GET = async (req, res) => {\n  res.json({})\n}\n\nexport const AUTHENTICATE = false\n",
      "/admin/commented"       => "// export const AUTHENTICATE = false\nexport const GET = async (req, res) => {\n  res.json({})\n}\n",
      "/rbac/roles"            => "export const GET = async (req, res) => {\n  res.json({})\n}\n",
      "/store/customers/me"    => "export const GET = async (req, res) => {\n  res.json({})\n}\n",
      "/store/items"           => "export const GET = async (req, res) => {\n  res.json({})\n}\n",
      "/administrators/report" => "export const GET = async (req, res) => {\n  res.json({})\n}\n",
      "/admin/let-export"      => "export const GET = async (req, res) => {\n  res.json({})\n}\nexport let AUTHENTICATE = false\n",
      "/admin/named-export"    => "export const GET = async (req, res) => {\n  res.json({})\n}\nconst AUTHENTICATE = false\nexport { AUTHENTICATE }\n",
      "/admin/zero"            => "export const GET = async (req, res) => {\n  res.json({})\n}\nexport const AUTHENTICATE = 0\n",
      "/admin/string-note"     => "export const GET = async (req, res) => {\n  res.json({})\n}\nconst note = 'export const AUTHENTICATE = false'\n",
      "/admin/truthy"          => "export const GET = async (req, res) => {\n  res.json({})\n}\nexport const AUTHENTICATE = true\n",
    }
    begin
      endpoints = routes.map do |url, source|
        file = "#{tmpdir}/src/api#{url}/route.ts"
        Dir.mkdir_p(File.dirname(file))
        File.write(file, source)
        details = Details.new(PathInfo.new(file, source.lines.index!(&.includes?("GET")) + 1))
        details.technology = "js_medusa"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      verdicts = MedusaAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {ep.url, ep.tags.map(&.description)} }
      verdicts["/admin/items"].should eq(["Protected by the Medusa router's default authentication on /admin"])
      verdicts["/admin/commented"].should eq(["Protected by the Medusa router's default authentication on /admin"])
      verdicts["/rbac/roles"].should eq(["Protected by the Medusa router's default authentication on /rbac"])
      verdicts["/store/customers/me"].should eq(["Protected by the Medusa router's default authentication on /store/customers/me"])
      verdicts["/admin/string-note"].should eq(["Protected by the Medusa router's default authentication on /admin"])
      verdicts["/admin/truthy"].should eq(["Protected by the Medusa router's default authentication on /admin"])
      %w[/admin/let-export /admin/named-export /admin/zero].each { |url| verdicts[url].should be_empty }
      verdicts["/admin/public-info"].should be_empty
      verdicts["/store/items"].should be_empty
      verdicts["/administrators/report"].should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
