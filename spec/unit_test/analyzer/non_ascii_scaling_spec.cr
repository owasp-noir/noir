require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# A per-route char-indexed String op (`MatchData#begin`, `String#match(re,
# pos)`, `String#[]`) walks from byte 0 once a file holds one multi-byte
# char, so a route loop built on them is quadratic on a file with a single
# Korean string or comment. Each case scans the same routes file twice — with
# `COMMENT` replaced by ASCII text, then by Korean — and requires the two to cost about
# the same and find the same endpoints.
private def scan_tree(root : String, tech : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  options["only_techs"] = YAML::Any.new(tech)
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

private def scan_with_comment(files : Hash(String, String), main : String, comment : String, tech : String) : Tuple(Array(Endpoint), Time::Span)
  root = File.tempname("noir-non-ascii")
  files.each do |rel, body|
    path = File.join(root, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, rel == main ? body.sub("COMMENT", comment) : body)
  end
  endpoints = [] of Endpoint
  elapsed = Time.measure { endpoints = scan_tree(root, tech) }
  {endpoints, elapsed}
ensure
  FileUtils.rm_rf(root) if root
end

private def assert_linear_on_non_ascii(files : Hash(String, String), main : String, tech : String)
  ascii, ascii_time = scan_with_comment(files, main, "plain comment", tech)
  korean, korean_time = scan_with_comment(files, main, "한글 주석", tech)
  korean.map(&.url).sort!.should eq(ascii.map(&.url).sort!)
  ascii.should_not be_empty
  korean_time.should be < (ascii_time * 3 + 1.second)
end

describe "non-ASCII route files" do
  it "keeps CakePHP route scans linear" do
    routes = (1..4000).join { |i| "    $builder->get('/about#{i}', ['controller' => 'Pages', 'action' => 'about#{i}']);\n" }
    assert_linear_on_non_ascii({
      "composer.json"     => %({"require":{"cakephp/cakephp":"^5.0"}}),
      "bin/cake"          => "#!/usr/bin/env php\n",
      "config/routes.php" => "<?php\n$title = 'COMMENT';\nreturn static function (RouteBuilder $routes) {\n  $routes->scope('/api', function (RouteBuilder $builder) {\n#{routes}  });\n};\n",
    }, "config/routes.php", "php_cakephp")
  end

  it "keeps Phalcon route scans linear" do
    routes = (1..1200).join do |i|
      "$router->add('/legacy#{i}', 'Info::show')->via(['POST']);\n$app->get('/items#{i}', function () { echo 'x'; });\n"
    end
    assert_linear_on_non_ascii({
      "composer.json" => %({"require":{"ext-phalcon":">=5.0"}}),
      "index.php"     => "<?php\nuse Phalcon\\Mvc\\Router;\n$title = 'COMMENT';\n#{routes}",
    }, "index.php", "php_phalcon")
  end

  it "keeps Laravel route scans linear" do
    routes = (1..1000).join do |i|
      "Route::get('/items#{i}/{id}', [ItemController::class, 'show']);\nRoute::post('/save#{i}', function (Request $request) { return $request->input('name'); });\n"
    end
    assert_linear_on_non_ascii({
      "composer.json"  => %({"require":{"laravel/framework":"^11.0"}}),
      "artisan"        => "#!/usr/bin/env php\n",
      "routes/web.php" => "<?php\nuse Illuminate\\Support\\Facades\\Route;\n$title = 'COMMENT';\n#{routes}",
    }, "routes/web.php", "php_laravel")
  end

  it "keeps Lumen route scans linear" do
    routes = (1..1500).join { |i| "$router->post('/users#{i}', function () { return $request->input('name'); });\n" }
    assert_linear_on_non_ascii({
      "composer.json"     => %({"require":{"laravel/lumen-framework":"^10.0"}}),
      "bootstrap/app.php" => "<?php\n$app = new Laravel\\Lumen\\Application(dirname(__DIR__));\n",
      "routes/web.php"    => "<?php\n$title = 'COMMENT';\n#{routes}",
    }, "routes/web.php", "php_lumen")
  end

  it "keeps ThinkPHP route scans linear" do
    routes = (1..800).join { |i| "Route::get('hello#{i}/:name', 'index/hello');\nRoute::rule('update#{i}', 'index/update', 'PUT');\n" }
    assert_linear_on_non_ascii({
      "composer.json" => %({"require":{"topthink/framework":"^8.0"}}),
      "think"         => "#!/usr/bin/env php\n",
      "route/app.php" => "<?php\nuse think\\facade\\Route;\n$title = 'COMMENT';\n#{routes}",
    }, "route/app.php", "php_thinkphp")
  end

  it "keeps Slim route scans linear" do
    routes = (1..1500).join { |i| "$app->get('/search#{i}', function ($request, $response) { return $response; });\n" }
    assert_linear_on_non_ascii({
      "composer.json" => %({"require":{"slim/slim":"^4.12"}}),
      "index.php"     => "<?php\nuse Slim\\Factory\\AppFactory;\n$title = 'COMMENT';\n$app = AppFactory::create();\n#{routes}",
    }, "index.php", "php_slim")
  end

  it "keeps Laminas route scans linear" do
    routes = (1..1500).join do |i|
      "    $app->route('/r#{i}', [H::class], ['GET'], 'r#{i}');\n    $app->get('/docs#{i}', function ($request) { return 1; });\n"
    end
    assert_linear_on_non_ascii({
      "composer.json"                     => %({"require":{"mezzio/mezzio":"^3.19"}}),
      "config/autoload/routes.global.php" => "<?php\nuse Mezzio\\Application;\n$title = 'COMMENT';\nreturn function (Application $app) {\n#{routes}};\n",
    }, "config/autoload/routes.global.php", "php_laminas")
  end

  it "keeps a Bun routes map linear" do
    routes = (1..1000).join { |i| "    '/items#{i}/:id': { GET: (req) => new Response('x'), POST: async (req) => Response.json(1) },\n" }
    assert_linear_on_non_ascii({
      "package.json" => %({"name":"x","devDependencies":{"@types/bun":"*"}}),
      "server.ts"    => "const title = 'COMMENT';\nBun.serve({\n  routes: {\n#{routes}  },\n});\n",
    }, "server.ts", "js_bun")
  end

  it "keeps node:http handler collection linear" do
    helpers = (1..800).join { |i| "const helper#{i} = (req, res) => { res.end('#{i}'); };\nfunction fn#{i}(req, res) { return 1; }\n" }
    assert_linear_on_non_ascii({
      "package.json" => %({"name":"x"}),
      "server.js"    => "const http = require('http');\nconst title = 'COMMENT';\n#{helpers}http.createServer((req, res) => {\n  if (req.method === 'POST' && req.url === '/users') { res.end('ok'); }\n}).listen(3000);\n",
    }, "server.js", "js_http")
  end
end
