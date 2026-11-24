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

  it "reads Yii access rules for a signed-in caller, keeping the ones it cannot read" do
    source = [
      "<?php",
      "class PostController extends Controller",
      "{",
      "    public function behaviors()",
      "    {",
      "        return ['access' => ['class' => AccessControl::class, 'rules' => [",
      "            ['actions' => ['login'], 'allow' => true, 'roles' => ['?']],",
      "            ['actions' => ['edit'], 'allow' => true, 'roles' => ['editor', 'admin']],",
      "            ['actions' => ['view'], 'allow' => true, 'roles' => ['@', User::ROLE_READER]],",
      "            ['actions' => ['audit'], 'allow' => true, 'roles' => ['@'], 'matchCallback' => fn () => true],",
      "        ]]];",
      "    }",
      "    public function actionEdit() {}",
      "    public function actionView() {}",
      "    public function actionAudit() {}",
      "}",
    ].join("\n")
    atoms(php_auth_tag(source, 13, "php_yii")).should eq([["role:admin", "role:editor"]])
    atoms(php_auth_tag(source, 14, "php_yii")).should eq([["authenticated"], ["unresolved"]])
    atoms(php_auth_tag(source, 15, "php_yii")).should eq([["authenticated"], ["unresolved"]])
  end

  it "leaves a Yii filter with its own rule class unread" do
    source = [
      "<?php",
      "class PostController extends Controller",
      "{",
      "    public function behaviors()",
      "    {",
      "        return ['access' => ['class' => AccessControl::class, 'ruleConfig' => ['class' => MyRule::class], 'rules' => [",
      "            ['allow' => true, 'roles' => ['@']],",
      "        ]]];",
      "    }",
      "    public function actionEdit() {}",
      "}",
    ].join("\n")
    atoms(php_auth_tag(source, 10, "php_yii")).should eq([["authenticated"], ["unresolved"]])
  end

  it "adds nothing to the Symfony analyzer's tag for an attribute it already read" do
    source = [
      "<?php",
      "class AdminController extends AbstractController",
      "{",
      "    #[Route('/x')]",
      "    #[IsGranted('ROLE_ADMIN')]",
      "    public function show() {}",
      "}",
    ].join("\n")
    analyzer = Tag.new("auth", "Protected by Symfony #[IsGranted('ROLE_ADMIN')]", "php_auth", requires: [
      Access::Clause.new([Access::Atom.new(:role, "ROLE_ADMIN")], "IsGranted('ROLE_ADMIN')"),
    ])
    tag = php_auth_tag(source, 6, "php_symfony", existing: analyzer).should_not be_nil
    tag.description.should eq("Protected by Symfony #[IsGranted('ROLE_ADMIN')]")
    atoms(tag).should eq([["role:ROLE_ADMIN"]])
  end

  it "keeps the unread one-line reading beside an access_control tag, and alone" do
    source = [
      "<?php",
      "class AdminController extends AbstractController",
      "{",
      "    #[IsGranted('ROLE_ADMIN')]",
      "    public function show() {}",
      "}",
    ].join("\n")
    access_control = Tag.new("auth", "Protected by Symfony access_control (ROLE_USER)", "php_auth", requires: [
      Access::Clause.new([Access::Atom.new(:role, "ROLE_USER")], "access_control (ROLE_USER)"),
    ])
    atoms(php_auth_tag(source, 5, "php_symfony", existing: access_control)).should eq([["role:ROLE_USER"], ["authenticated"], ["unresolved"]])
    php_auth_tag(source, 5, "php_symfony").try(&.requires).should be_nil
  end

  it "leaves Yii rules unread when another filter or a spread entry also applies" do
    two_filters = [
      "<?php",
      "class AdminController extends Controller",
      "{",
      "    public function behaviors()",
      "    {",
      "        return [",
      "            'login' => ['class' => AccessControl::class, 'rules' => [['allow' => true, 'roles' => ['@']]]],",
      "            'admin' => ['class' => AccessControl::class, 'rules' => [['allow' => true, 'roles' => ['admin']]]],",
      "        ];",
      "    }",
      "    public function actionDelete() {}",
      "}",
    ].join("\n")
    atoms(php_auth_tag(two_filters, 11, "php_yii")).should eq([["authenticated"], ["unresolved"]])
    spread = [
      "<?php",
      "class SpreadController extends Controller",
      "{",
      "    public function behaviors()",
      "    {",
      "        return ['access' => ['class' => AccessControl::class, 'rules' => [['allow' => true, 'roles' => ['@'], ...$extra]]]];",
      "    }",
      "    public function actionView() {}",
      "}",
    ].join("\n")
    atoms(php_auth_tag(spread, 8, "php_yii")).should eq([["authenticated"], ["unresolved"]])
  end

  it "keeps CakePHP's Authorization layer unread beside the identity check" do
    tmpdir = File.tempname("php_cake_authz")
    controllers = File.join(tmpdir, "src", "Controller")
    Dir.mkdir_p(controllers)
    Dir.mkdir_p(File.join(tmpdir, "config"))
    routes = File.join(tmpdir, "config", "routes.php")
    File.write(routes, "<?php\n$routes->connect('/articles/edit', ['controller' => 'Articles', 'action' => 'edit']);\n")
    File.write(File.join(controllers, "ArticlesController.php"), <<-PHP)
      <?php
      class ArticlesController extends Controller
      {
          public function initialize(): void
          {
              $this->loadComponent('Authentication.Authentication');
              $this->loadComponent('Authorization.Authorization');
          }
          public function edit($id) { $this->Authorization->authorize($this->Articles->get($id)); }
      }
      PHP
    begin
      options = create_test_options
      options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(routes, 2))
      details.technology = "php_cakephp"
      endpoint = PhpAuthTagger.new(options).perform([Endpoint.new("/articles/edit", "GET", [] of Param, details)])[0]
      atoms(endpoint.tags.find(&.tagger.==("php_auth"))).should eq([["authenticated"], ["unresolved"]])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
