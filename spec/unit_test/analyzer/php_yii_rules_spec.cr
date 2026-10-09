require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/yii"

private def yii_rule_routes(rules : String) : Array(String)
  dir = File.tempname("noir_yii_rules")
  path = File.join(dir, "config/web.php")
  Dir.mkdir_p(File.dirname(path))
  File.write(path, "<?php\nreturn ['components' => ['urlManager' => ['rules' => [\n#{rules}\n]]]];\n")
  Analyzer::Php::Yii.new(create_test_options).analyze_file(path).map { |e| "#{e.method} #{e.url}" }.sort!
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "Analyzer::Php::Yii urlManager rules" do
  it "splits verbs the way UrlManager does: case-sensitive, with a pattern" do
    yii_rule_routes(<<-PHP).should eq(["GET /POST", "GET /delete", "GET /get", "GET /posts", "HEAD /posts"])
      'get' => 'site/get',
      'delete' => 'site/delete',
      'POST' => 'site/post',
      'GET,HEAD posts' => 'post/index',
      PHP
  end

  it "applies a GroupUrlRule prefix to the rules it declares" do
    yii_rule_routes(<<-'PHP').should eq(["GET /admin/login", "GET /admin/stats/{id}", "POST /admin/logout", "POST /admin/stats/{id}"])
      ['class' => 'yii\web\GroupUrlRule', 'prefix' => 'admin', 'routePrefix' => 'adm', 'rules' => [
          'login' => 'user/login',
          'POST logout' => 'user/logout',
          ['pattern' => 'stats/<id:\d+>', 'route' => 'stats/view', 'verb' => ['GET', 'POST']],
      ]],
      PHP
  end

  it "reads an array rule declared under a string key" do
    yii_rule_routes(<<-'PHP').should eq(["GET /kg/in", "PUT /keyed/{id}"])
      'keyed-group' => ['class' => 'yii\web\GroupUrlRule', 'prefix' => 'kg', 'rules' => ['in' => 'a/in']],
      'keyed' => ['pattern' => 'keyed/<id>', 'route' => 'k/view', 'verb' => 'PUT'],
      PHP
  end

  it "replaces the REST defaults with a rule's own patterns" do
    yii_rule_routes(<<-'PHP').should eq(["GET /users/search", "GET /users/{id}", "POST /users"])
      ['class' => 'yii\rest\UrlRule', 'controller' => 'user',
       'patterns' => ['GET {id}' => 'view', 'POST' => 'create'],
       'extraPatterns' => ['GET search' => 'search']],
      PHP
  end

  it "honours pluralize, only, except and extraPatterns on a REST rule" do
    yii_rule_routes(<<-'PHP').should eq([
      ['class' => 'yii\rest\UrlRule', 'controller' => 'person', 'pluralize' => false, 'only' => ['index', 'view']],
      ['class' => 'yii\rest\UrlRule', 'controller' => ['v1/user'], 'except' => ['delete', 'options', 'create', 'update'],
       'extraPatterns' => ['GET search' => 'search', 'POST {id}/like' => 'like']],
      PHP
      "GET /person", "GET /person/{id}", "GET /v1/users", "GET /v1/users/search", "GET /v1/users/{id}",
      "HEAD /person", "HEAD /person/{id}", "HEAD /v1/users", "HEAD /v1/users/{id}", "POST /v1/users/{id}/like",
    ])
  end

  # The rules walk slices the source once per array-style rule; with
  # `String#[]` that is O(offset) on multi-byte text, so 20k rules carrying
  # CJK strings took minutes.
  it "stays linear on many array rules with multi-byte strings" do
    dir = File.tempname("noir_yii_rules")
    path = File.join(dir, "config/web.php")
    Dir.mkdir_p(File.dirname(path))
    rules = "['x' => '注释'],\n" * 20_000
    File.write(path, "<?php\nreturn ['components' => ['urlManager' => ['rules' => [\n#{rules}'GET,HEAD a' => 'b']]]];\n")

    begin
      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Php::Yii.new(create_test_options).analyze_file(path) }
      endpoints.map { |e| "#{e.method} #{e.url}" }.sort!.should eq(["GET /a", "HEAD /a"])
      elapsed.should be < 2.seconds
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
