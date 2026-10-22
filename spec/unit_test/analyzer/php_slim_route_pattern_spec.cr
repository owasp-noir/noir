require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/slim"

# Runs the Slim analyzer on `source` and returns "METHOD url", sorted.
private def slim_routes(source : String) : Array(String)
  dir = File.tempname("noir_slim_pattern")
  path = File.join(dir, "index.php")
  Dir.mkdir_p(dir)
  File.write(path, source)
  Analyzer::Php::Slim.new(create_test_options).analyze_file(path).map { |e| "#{e.method} #{e.url}" }.sort!
ensure
  FileUtils.rm_rf(dir) if dir
end

# A Slim route pattern is empty (the group's own path), starts with `/`, or
# is an optional segment `[...]`. Config getters, HTTP clients and
# collections share the `$x->get('literal', ...)` shape and must not read as
# routes, whether or not the file names `Slim\`.
describe "Slim route pattern shape" do
  it "keeps real patterns in a file that names Slim" do
    slim_routes(<<-PHP).should eq(["GET /ok", "GET /users", "GET /users/[/{id}]", "POST /users/{id}"])
      <?php
      use Slim\\Factory\\AppFactory;
      $app->get('/ok', fn ($req, $res) => $res);
      $app->group('/users', function ($g) {
          $g->get('', X::class);
          $g->get('[/{id}]', X::class);
          $g->post('/{id}', X::class);
      });
      PHP
  end

  it "does not read config getters, HTTP clients or collections as routes" do
    slim_routes(<<-PHP).should eq(["GET /ok"])
      <?php
      use Slim\\Factory\\AppFactory;
      date_default_timezone_set($conf->get('general.timezone', 'UTC'));
      $res = $http->get('https://api.example.com/v1/users', []);
      $messages->put("$key", $message);
      $app->get('/ok', fn ($req, $res) => $res);
      PHP
  end

  it "does not read a getter in a marker-less file as a route" do
    slim_routes(<<-PHP).should be_empty
      <?php
      $this->escape = $conf->get('security.markdown_escape', true);
      $cache->delete('entityDefs', $scope);
      PHP
  end

  it "applies the same shape to map() routes" do
    slim_routes(<<-PHP).should eq(["GET /both", "POST /both"])
      <?php
      use Slim\\Factory\\AppFactory;
      $app->map(['GET', 'POST'], '/both', fn ($req, $res) => $res);
      $bag->map(['GET'], 'not-a-route', fn ($x) => $x);
      PHP
  end
end
