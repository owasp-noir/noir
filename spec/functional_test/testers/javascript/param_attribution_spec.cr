require "../../func_spec.cr"

# #3272: each handler gets the inputs it reads, and only those.
describe "JavaScript param attribution", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
    Noir::JSHandlerResolver.reset
  end

  params_for = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/#{fixture}/")])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints.to_h do |e|
      {"#{e.method} #{e.url}", {e.params.map { |p| "#{p.name}:#{p.param_type}" }.sort!, e.details.code_paths.first?.try(&.line)}}
    end
  end

  it "keeps Express params on their own handler and reads multer fields" do
    rows = params_for.call("express_param_attribution")
    # Async closures in a router factory that takes a parameter.
    rows["GET /shop/a"][0].should eq(["qa:query"])
    rows["GET /shop/b"][0].should eq(["qb:query"])
    # Writes to req.headers / req.query / req.body set defaults; `||=` and
    # `==` still read.
    rows["GET /items"][0].should be_empty
    rows["GET /defaults"][0].should eq(["limit:query", "sort:query"])
    rows["POST /icons"][0].should eq(["banner:file", "icon:file"])
    rows["POST /avatar"][0].should eq(["avatar:file"])
    rows["POST /photos"][0].should eq(["photos:file"])
  end

  it "reads @koa/multer fields" do
    rows = params_for.call("koa_multer")
    rows["POST /icons"][0].should eq(["icon:file"])
    rows["POST /avatar"][0].should eq(["avatar:file"])
  end

  it "scopes wrapped Next.js exports and reads destructured server-action args" do
    rows = params_for.call("nextjs_param_attribution")
    rows["PUT /api/items"].should eq({["x-owner-id:header"], 3})
    rows["DELETE /api/items"].should eq({["x-tenant-id:header"], 8})
    rows["GET /api/items"].should eq({["page:query"], 13})
    # The wrapped same-file handler still reads the helper it calls, not GET's `sort`.
    rows["POST /api/checked"][0].should eq(["name:json", "x-api-key:header"])
    rows["POST /updateItem"][0].should eq(["id:body", "name:body"])
    rows["POST /deleteItem"][0].should eq(["id:body"])
    rows["POST /createItem"][0].should eq(["name:body", "price:body"])
  end
end
