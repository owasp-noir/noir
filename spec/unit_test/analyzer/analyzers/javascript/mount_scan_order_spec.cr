require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/express"
require "../../../../../src/analyzer/analyzers/javascript/hono"

# Express and Hono both run a RouterMountScanner into the one CodeLocator
# prefix table. Hono's scanner skips Express files, so its pass 3 ("place an
# unplaced mount at the root if nothing else reached the child") placed
# `router.use('/api/v3/groups', …)` onto groups.js without having seen
# `app.use('/legacy', groups())` — and Express's output then depended on
# which analyzer started first.
private def express_routes_after(order : Array(Symbol)) : Array(String)
  root = File.expand_path("../../../../functional_test/fixtures/javascript/express_injected_router_mount", __DIR__)
  locator = CodeLocator.instance
  locator.clear_all
  Dir.glob(File.join(root, "**", "*")).each do |path|
    locator.register_file(path, File.read(path)) if File.file?(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])

  routes = [] of String
  order.each do |framework|
    case framework
    when :hono
      Analyzer::Javascript::Hono.new(options).analyze
    else
      routes = Analyzer::Javascript::Express.new(options).analyze.map { |e| "#{e.method} #{e.url}" }.sort!
    end
  end
  routes
ensure
  CodeLocator.instance.clear_all
end

describe "JS router mount scan order" do
  it "gives Express the same routes whether or not Hono's scanner ran first" do
    alone = express_routes_after([:express])
    express_routes_after([:hono, :express]).should eq(alone)
    alone.should_not contain("GET /api/v3/groups/:gid")
    alone.should contain("GET /legacy/:gid")
  end
end
