require "../../func_spec.cr"

# `graphql_operation` used to be a `FileAnalyzer` hook rather than a
# registered technology, and the file analyzer runs on every scan regardless
# of which technologies were selected. Two things followed, and this fixture
# pins both of them:
#
#   * the `POST /graphql` endpoint came out with `"technology": null`, so no
#     report could group it and no per-technology view contained it;
#   * `--only-techs <T>` returned it in addition to whatever T produced —
#     measured on the hoppscotch corpus as six technologies each reporting
#     one endpoint their analyzer had not produced.
#
# `FunctionalTester` asserts urls, methods and params but not
# `details.technology`, and it cannot pass `--only-techs`, so these run the
# scan directly.
private def scan(only_techs : String = "") : Array(Endpoint)
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new([YAML::Any.new(
    "./spec/functional_test/fixtures/specification/graphql_operation_scope/")])
  options["nolog"] = YAML::Any.new(true)
  options["only_techs"] = YAML::Any.new(only_techs)

  # Process-wide singleton; whichever spec ran before must not leak its file
  # map into this scan. Same reset `FunctionalTester#ensure_scanned` makes.
  CodeLocator.instance.clear_all
  app = NoirRunner.new options
  app.detect
  app.analyze
  app.endpoints
end

describe "graphql operation documents are a technology", tags: "functional" do
  it "attributes every endpoint of a full scan to a technology" do
    endpoints = scan

    untagged = endpoints.select { |ep| ep.details.technology.nil? }
    fail "endpoints with no technology: #{untagged.map(&.url)}" unless untagged.empty?
  end

  it "attributes the operation document to graphql_operation" do
    endpoint = scan.find { |ep| ep.url == "/graphql" }

    endpoint.should_not be_nil
    endpoint.try &.details.technology.should eq "graphql_operation"
  end

  # The other half of the same file: an SDL schema is `graphql_sdl`'s, and
  # the operation detector must not claim it. The two analyzers read the same
  # extensions, so "one claims the other's documents" is the failure mode
  # closest to hand.
  it "leaves the SDL schema to graphql_sdl" do
    endpoint = scan.find { |ep| ep.url == "/graphql#Query.user" }

    endpoint.should_not be_nil
    endpoint.try &.details.technology.should eq "graphql_sdl"
  end

  it "returns nothing of its own under --only-techs graphql_sdl" do
    urls = scan(only_techs: "graphql_sdl").map(&.url)

    urls.should contain "/graphql#Query.user"
    urls.should_not contain "/graphql"
  end

  it "is selectable on its own with --only-techs graphql_operation" do
    urls = scan(only_techs: "graphql_operation").map(&.url)

    urls.should eq ["/graphql"]
  end

  # An unrelated technology must come back with exactly what its own
  # analyzer produced — nothing here, because this fixture has no Rails app.
  it "adds nothing to an unrelated --only-techs run" do
    scan(only_techs: "ruby_rails").should be_empty
  end
end
