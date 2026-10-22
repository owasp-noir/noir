require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/slim"

# Runs the Slim analyzer on `source` and returns "METHOD url", sorted.
private def interpolated_slim_routes(source : String) : Array(String)
  dir = File.tempname("noir_slim_interpolated")
  path = File.join(dir, "index.php")
  Dir.mkdir_p(dir)
  File.write(path, source)
  Analyzer::Php::Slim.new(create_test_options).analyze_file(path).map { |e| "#{e.method} #{e.url}" }.sort!
ensure
  FileUtils.rm_rf(dir) if dir
end

# A route written with an interpolated prefix (`"{$apiPrefix}/users"`,
# `"$base/login"`) is still a route; a bare interpolated string is the shape
# of a collection `put("$key", …)` and is not. (The analyzer leaves a
# top-level pattern as written; the leading `/` is added after it.)
describe "Slim interpolated route pattern" do
  it "keeps a route that starts with an interpolated prefix" do
    interpolated_slim_routes(<<-PHP).should eq(["GET /ok", "GET {apiPrefix}/users", "POST {base}/login"])
      <?php
      use Slim\\Factory\\AppFactory;
      $app->get("{$apiPrefix}/users", fn ($req, $res) => $res);
      $app->post("$base/login", fn ($req, $res) => $res);
      $app->get('/ok', fn ($req, $res) => $res);
      $messages->put("$key", $message);
      $conf->get('general.timezone', 'UTC');
      PHP
  end

  it "keeps an interpolated prefix inside a group and in map()" do
    interpolated_slim_routes(<<-PHP).should eq(["GET /admin/{section}/list", "GET {apiPrefix}/both", "POST {apiPrefix}/both"])
      <?php
      use Slim\\Factory\\AppFactory;
      $app->group('/admin', function ($g) {
          $g->get("$section/list", fn ($req, $res) => $res);
      });
      $app->map(['GET', 'POST'], "{$apiPrefix}/both", fn ($req, $res) => $res);
      $bag->map(['GET'], "$name", fn ($x) => $x);
      PHP
  end

  it "still rejects non-route string shapes" do
    interpolated_slim_routes(<<-PHP).should be_empty
      <?php
      $res = $http->get('https://api.example.com/v1/users', []);
      $messages->put("$key", $message);
      $messages->put("{$key}", $message);
      $this->escape = $conf->get('security.markdown_escape', true);
      PHP
  end
end
