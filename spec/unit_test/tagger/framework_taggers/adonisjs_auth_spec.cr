require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# adonisjs_auth/start/routes.ts: `middleware.auth()` on a route, on a
# group, first in a list and on an outer group; `silentAuth`, `guest`, no
# middleware and a group without it (#3308).
describe "AdonisjsAuthTagger" do
  base = File.expand_path("../../../functional_test/fixtures/javascript/adonisjs_auth", __DIR__)
  routes = "#{base}/start/routes.ts"

  it "tags routes behind middleware.auth() on the route or an enclosing group" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    lines = {5 => "/notes", 6 => "/notes/:id", 9 => "/api/notes", 13 => "/public", 16 => "/feed", 17 => "/login",
             20 => "/admin", 25 => "/account/me", 28 => "/account/inner/drafts", 37 => "/v2/open",
             42 => "/posts", 43 => "/drafts"}
    endpoints = lines.map do |line, url|
      details = Details.new(PathInfo.new(routes, line))
      details.technology = "js_adonisjs"
      Endpoint.new(url, "GET", [] of Param, details)
    end

    verdicts = AdonisjsAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {ep.url, ep.tags.map(&.description)} }
    verdicts["/notes"].should eq(["Protected by AdonisJS middleware.auth()"])
    verdicts["/notes/:id"].should eq(["Protected by AdonisJS middleware.auth()"])
    verdicts["/api/notes"].should eq(["Protected by AdonisJS middleware.auth() on its route group"])
    verdicts["/admin"].should eq(["Protected by AdonisJS middleware.auth()"])
    verdicts["/account/me"].should eq(["Protected by AdonisJS middleware.auth() on its route group"])
    verdicts["/account/inner/drafts"].should eq(["Protected by AdonisJS middleware.auth() on its route group"])
    verdicts["/posts"].should eq(["Protected by AdonisJS middleware.auth()"])
    %w[/public /feed /login /v2/open /drafts].each { |url| verdicts[url].should be_empty }
  end

  it "targets AdonisJS" do
    AdonisjsAuthTagger.target_techs.should eq(["js_adonisjs"])
  end

  # `é` is two bytes. The chained `.use` sits after it, and the bare
  # `router` line must not read the next call.
  it "reads a multibyte call by bytes and stays on its line" do
    tmpdir = File.tempname("adonis_auth_bytes")
    Dir.mkdir_p("#{tmpdir}/start")
    routes = "#{tmpdir}/start/routes.ts"
    File.write(routes, "router.get('/café', () => {}).use(middleware.auth())\nrouter\nrouter.group(() => {\n  router.get('/café/notes', () => {})\n}).use(middleware.auth())\nrouter.get('/open', () => {})\n")
    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      endpoints = [{1, "/cafe"}, {2, "/blank"}, {4, "/notes"}, {6, "/open"}].map do |line, url|
        details = Details.new(PathInfo.new(routes, line))
        details.technology = "js_adonisjs"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      verdicts = AdonisjsAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {ep.url, ep.tags.map(&.description)} }
      verdicts["/cafe"].should eq(["Protected by AdonisJS middleware.auth()"])
      verdicts["/notes"].should eq(["Protected by AdonisJS middleware.auth() on its route group"])
      verdicts["/blank"].should be_empty
      verdicts["/open"].should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
