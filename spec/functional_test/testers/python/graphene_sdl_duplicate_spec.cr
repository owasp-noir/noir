require "../../func_spec.cr"

# A dumped `schema.graphql` names no mount, so the SDL analyzer falls back
# to `/graphql`; the code mounts the same schema at `graphql/`. One
# operation, reported under the code's mount, with both locations.
tester = FunctionalTester.new("fixtures/python/graphene_sdl_duplicate/", {
  :techs     => 3,
  :endpoints => 2,
}, [
  Endpoint.new("/graphql/#Query.me", "POST"),
  Endpoint.new("/graphql/", "GET"),
])
tester.perform_tests

it "merges the SDL operation into the code's", tags: "functional" do
  ep = tester.endpoints.find! { |e| e.url == "/graphql/#Query.me" }
  ep.details.code_paths.map { |p| File.basename(p.path) }.sort!.should eq(["schema.graphql", "schema.py"])
end
