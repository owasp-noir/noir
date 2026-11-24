require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `source` as a routes file, tags the endpoint declared on `line`
# with `technology`, and returns its php_auth tag.
# `existing` stands in for a tag the analyzer put on the route first.
private def php_auth_tag(source : String, line : Int32, technology : String = "php_laravel", existing : Tag? = nil) : Tag?
  tmpdir = File.tempname("php_auth_requires")
  Dir.mkdir_p(tmpdir)
  routes = File.join(tmpdir, "web.php")
  File.write(routes, source)
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(routes, line))
  details.technology = technology
  endpoint = Endpoint.new("/x", "GET", [] of Param, details)
  existing.try { |tag| endpoint.add_tag(tag) }
  endpoint = PhpAuthTagger.new(options).perform([endpoint])[0]
  FileUtils.rm_rf(tmpdir)
  endpoint.tags.find(&.tagger.==("php_auth"))
end

private def atoms(tag : Tag?) : Array(Array(String))?
  tag.try(&.requires).try &.map(&.any_of.map(&.to_s))
end

describe "PhpAuthTagger requires" do
  it "reads a route's auth middleware as signed in" do
    tag = php_auth_tag("<?php\nRoute::get('/x', fn () => 1)->middleware('auth:sanctum');\n", 2)
    atoms(tag).should eq([["authenticated"]])
    tag.try(&.requires).try(&.first.source).should eq("auth:sanctum")
  end

  it "leaves requires unset for a route of another framework" do
    tag = php_auth_tag("<?php\nRoute::get('/x', fn () => 1)->middleware('auth');\n", 2, "php_slim").should_not be_nil
    tag.requires.should be_nil
  end

  it "reads the verified middleware as unread, with the conservative signed-in floor" do
    atoms(php_auth_tag("<?php\nRoute::get('/x', fn () => 1)->middleware('verified');\n", 2)).should eq([["unresolved"], ["authenticated"]])
  end

  it "reads every entry of the matched list, keeping what it cannot read" do
    source = "<?php\nRoute::get('/x', fn () => 1)->middleware(['auth', 'can:edit,post', 'role:admin', 'throttle:6,1']);\n"
    atoms(php_auth_tag(source, 2)).should eq([["authenticated"], ["permission:edit"], ["unresolved"]])
  end

  it "adds only what it read when the analyzer already tagged the route" do
    source = "<?php\nRoute::get('/x', fn () => 1)->middleware(['auth', 'role:admin']);\n"
    analyzer = Tag.new("auth", "Protected by Laravel auth middleware", "php_auth", requires: [
      Access::Clause.new([Access::Atom.new(:authenticated)], "auth"),
      Access::Clause.new([Access::Atom.new(:role, "admin")], "role:admin"),
    ])
    atoms(php_auth_tag(source, 2, existing: analyzer)).should eq([["authenticated"], ["role:admin"]])
  end

  it "reads the group middleware it matched, keeping the tag text" do
    source = [
      "<?php",
      "Route::group(['middleware' => 'verified'], function () {",
      "    Route::get('/x', fn () => 1);",
      "});",
    ].join("\n")
    tag = php_auth_tag(source, 3).should_not be_nil
    tag.description.should eq("Protected by Laravel auth middleware (group)")
    atoms(tag).should eq([["unresolved"], ["authenticated"]])
    tag.requires.try(&.first.any_of.first.value).should eq("verified")
  end

  it "reads a literal policy call as the ability" do
    source = [
      "<?php",
      "Route::put('/x/{post}', function (Post $post) {",
      "    $this->authorize('update', $post);",
      "    return $post;",
      "});",
    ].join("\n")
    atoms(php_auth_tag(source, 2)).should eq([["permission:update"]])
  end

  it "keeps the conservative reading for a check that does not refuse a guest" do
    source = [
      "<?php",
      "Route::get('/x', function () {",
      "    if (Gate::allows('see-extra')) { return 2; }",
      "    return 1;",
      "});",
    ].join("\n")
    tag = php_auth_tag(source, 2).should_not be_nil
    tag.description.should eq("Protected by Laravel Gate authorization")
    atoms(tag).should eq([["authenticated"], ["unresolved"]])
  end
end
