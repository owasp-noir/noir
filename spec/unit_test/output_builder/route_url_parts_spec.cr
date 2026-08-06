require "../../spec_helper"
require "../../../src/output_builder/oas2"
require "../../../src/output_builder/oas3"
require "../../../src/output_builder/postman"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"
require "json"

# The parts of an endpoint URL that a `paths` key or a Postman URL cannot
# hold: the route's own query string, the `#fragment` Noir uses to address
# many operations on one path, and the authority of an absolute URL. Every
# builder that reconstructs a URL used to drop them.
private def builder_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
    "url"     => YAML::Any.new(""),
  }
end

private def render(builder, endpoints)
  builder.io = IO::Memory.new
  builder.print(endpoints)
  JSON.parse(builder.io.to_s)
end

describe "route URL parts in reconstructing builders" do
  describe "inline query string" do
    it "keeps the values that address each handler as an oas3 enum" do
      # Two WordPress AJAX handlers behind one PHP file.
      first = Endpoint.new("/wp-admin/admin-ajax.php?action=get_user_data", "POST")
      first.push_param(Param.new("action", "", "query"))
      second = Endpoint.new("/wp-admin/admin-ajax.php?action=save_settings", "POST")
      second.push_param(Param.new("action", "", "query"))

      doc = render(OutputBuilderOas3.new(builder_options), [first, second])
      parameters = doc["paths"]["/wp-admin/admin-ajax.php"]["post"]["parameters"].as_a
      parameters.size.should eq(1)
      parameters[0]["name"].as_s.should eq("action")
      parameters[0]["in"].as_s.should eq("query")
      parameters[0]["schema"]["enum"].as_a.map(&.as_s).should eq(["get_user_data", "save_settings"])
    end

    it "keeps them as an oas2 enum" do
      endpoint = Endpoint.new("/index.cfm?method=ping", "GET")

      doc = render(OutputBuilderOas2.new(builder_options), [endpoint])
      parameters = doc["paths"]["/index.cfm"]["get"]["parameters"].as_a
      parameters[0]["enum"].as_a.map(&.as_s).should eq(["ping"])
    end

    it "records a declared override alongside the route's own value" do
      endpoint = Endpoint.new("/admin.php?action=list", "GET")
      endpoint.push_param(Param.new("action", "delete", "query"))

      doc = render(OutputBuilderOas3.new(builder_options), [endpoint])
      parameters = doc["paths"]["/admin.php"]["get"]["parameters"].as_a
      parameters.size.should eq(1)
      parameters[0]["schema"]["enum"].as_a.map(&.as_s).should eq(["list", "delete"])
    end

    it "leaves a plain query param unconstrained" do
      endpoint = Endpoint.new("/search", "GET")
      endpoint.push_param(Param.new("q", "", "query"))

      doc = render(OutputBuilderOas3.new(builder_options), [endpoint])
      parameters = doc["paths"]["/search"]["get"]["parameters"].as_a
      parameters[0]["schema"].as_h.has_key?("enum").should be_false
    end

    it "gives postman one query list built from the route" do
      endpoint = Endpoint.new("/wp-admin/admin-ajax.php?action=save_settings", "POST")
      endpoint.push_param(Param.new("action", "", "query"))

      doc = render(OutputBuilderPostman.new(builder_options), [endpoint])
      url = doc["item"][0]["request"]["url"]
      url["query"].as_a.size.should eq(1)
      url["query"][0]["key"].as_s.should eq("action")
      url["query"][0]["value"].as_s.should eq("save_settings")
      url["raw"].as_s.should eq("{{baseUrl}}/wp-admin/admin-ajax.php?action=save_settings")
    end
  end

  describe "many-operations-one-path fragment" do
    it "lists every GraphQL operation the merged oas3 operation covers" do
      endpoints = ["Query.users", "Mutation.createUser", "Subscription.userAdded"].map do |name|
        Endpoint.new("/graphql##{name}", "POST")
      end

      doc = render(OutputBuilderOas3.new(builder_options), endpoints)
      operation = doc["paths"]["/graphql"]["post"]
      operation["x-noir-operations"].as_a.map(&.as_s).should eq(
        ["Query.users", "Mutation.createUser", "Subscription.userAdded"])
    end

    it "lists them for oas2 too" do
      endpoints = ["eth_blockNumber", "eth_getBalance"].map { |name| Endpoint.new("/rpc##{name}", "POST") }

      doc = render(OutputBuilderOas2.new(builder_options), endpoints)
      doc["paths"]["/rpc"]["post"]["x-noir-operations"].as_a.map(&.as_s).should eq(
        ["eth_blockNumber", "eth_getBalance"])
    end

    it "gives every postman item a distinct name without putting it in the request URL" do
      endpoints = ["Query.users", "Mutation.createUser"].map { |name| Endpoint.new("/graphql##{name}", "POST") }

      doc = render(OutputBuilderPostman.new(builder_options), endpoints)
      doc["item"].as_a.map(&.["name"].as_s).should eq(
        ["POST /graphql#Query.users", "POST /graphql#Mutation.createUser"])
      doc["item"][0]["request"]["url"]["raw"].as_s.should eq("{{baseUrl}}/graphql")
    end
  end

  describe "absolute URL authority" do
    it "keeps both hosts when two absolute endpoints collapse onto one oas3 operation" do
      endpoints = [
        Endpoint.new("https://demo.example.com/api/users", "GET"),
        Endpoint.new("https://demo.example.com.evil/api/users", "GET"),
      ]

      doc = render(OutputBuilderOas3.new(builder_options), endpoints)
      doc["paths"]["/api/users"]["get"]["servers"].as_a.map(&.["url"].as_s).should eq(
        ["https://demo.example.com", "https://demo.example.com.evil"])
    end

    it "records them on the oas2 operation, which has no per-operation host" do
      endpoints = [
        Endpoint.new("https://a.example.com/api/users", "GET"),
        Endpoint.new("https://b.example.com/api/users", "GET"),
      ]

      doc = render(OutputBuilderOas2.new(builder_options), endpoints)
      doc["paths"]["/api/users"]["get"]["x-noir-hosts"].as_a.map(&.as_s).should eq(
        ["https://a.example.com", "https://b.example.com"])
    end

    it "leaves a relative endpoint with no server override" do
      doc = render(OutputBuilderOas3.new(builder_options), [Endpoint.new("/api/users", "GET")])
      doc["paths"]["/api/users"]["get"].as_h.has_key?("servers").should be_false
    end
  end

  describe "route syntax that is not a query" do
    it "does not truncate a regex route at its `?`" do
      # Drogon `/grp/(?:a|b)/(.*)?` used to emit the path `/grp/(` and a query
      # parameter named `:a|b)/(.*)?`.
      doc = render(OutputBuilderOas3.new(builder_options), [Endpoint.new("/grp/(?:a|b)/(.*)?", "GET")])
      doc["paths"].as_h.keys.should eq(["/grp/({a}|b)/(.{wildcard})"])
    end

    it "keeps an optional trailing segment in the postman path" do
      # Giraffe `/legacy(/?)` used to import as `{{baseUrl}}/legacy(?)=`.
      doc = render(OutputBuilderPostman.new(builder_options), [Endpoint.new("/legacy(/?)", "GET")])
      url = doc["item"][0]["request"]["url"]
      url["raw"].as_s.should eq("{{baseUrl}}/legacy(/?)")
      url.as_h.has_key?("query").should be_false
    end

    it "still treats a real key=value pair as a query" do
      doc = render(OutputBuilderPostman.new(builder_options), [Endpoint.new("/geo/:ip?", "GET")])
      doc["item"][0]["request"]["url"]["raw"].as_s.should eq("{{baseUrl}}/geo/:ip?")
    end
  end
end

describe "operation methods the emitted version supports" do
  it "reports an explicit TRACE endpoint as unsupported in oas2" do
    doc = render(OutputBuilderOas2.new(builder_options), [Endpoint.new("/debug", "TRACE")])
    doc["paths"]["/debug"].as_h.has_key?("trace").should be_false
    doc["paths"]["/debug"]["x-noir-unsupported-methods"].as_a.map(&.as_s).should eq(["TRACE"])
  end

  it "keeps trace in oas3, where the Path Item Object has the field" do
    doc = render(OutputBuilderOas3.new(builder_options), [Endpoint.new("/debug", "TRACE")])
    doc["paths"]["/debug"].as_h.has_key?("trace").should be_true
  end
end
