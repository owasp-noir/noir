require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/slim"
require "../../../src/analyzer/analyzers/php/codeigniter"
require "../../../src/analyzer/analyzers/php/cakephp"
require "../../../src/analyzer/analyzers/php/wordpress"
require "../../../src/analyzer/analyzers/php/yii"
require "../../../src/analyzer/analyzers/php/laminas"

# Writes `source` to `relative` under a temp dir, runs `analyzer` on it and
# returns "METHOD url Lline" for every endpoint, sorted.
private def php_route_lines(analyzer : FileScanEngine, relative : String, source : String) : Array(String)
  dir = File.tempname("noir_php_lines")
  path = File.join(dir, relative)
  Dir.mkdir_p(File.dirname(path))
  File.write(path, source)
  analyzer.analyze_file(path)
    .map { |e| "#{e.method} #{e.url} L#{e.details.code_paths.first?.try(&.line)}" }.sort!
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "PHP route line numbers" do
  options = create_test_options

  it "reports Slim route lines, inside groups too" do
    php_route_lines(Analyzer::Php::Slim.new(options), "app/routes.php", <<-PHP).should eq(["GET /a L4", "GET /g/b L6", "POST /g/c L7"])
      <?php
      use Slim;

      $app->get('/a', fn ($req, $res) => $res);
      $app->group('/g', function ($group) {
          $group->get('/b', B::class);
          $group->map(['POST'], '/c', C::class);
      });
      PHP
  end

  it "reports CodeIgniter route lines after a stripped group" do
    php_route_lines(Analyzer::Php::CodeIgniter.new(options), "app/Config/Routes.php", <<-PHP).should eq(["GET /admin/users L4", "GET /photos L8", "POST /login L7"])
      <?php

      $routes->group('admin', static function ($routes) {
          $routes->get('users', 'Admin::users');
      });

      $routes->post('login', 'Auth::login');
      $routes->resource('photos', ['only' => ['index']]);
      PHP
  end

  it "reports CakePHP route lines, inside scopes too" do
    php_route_lines(Analyzer::Php::CakePHP.new(options), "config/routes.php", <<-PHP).should eq(["GET /api/recipes L5", "GET /home L3"])
      <?php
      return function (RouteBuilder $routes): void {
          $routes->connect('/home', ['controller' => 'Pages', 'action' => 'home']);
          $routes->scope('/api', function (RouteBuilder $builder): void {
              $builder->resources('Recipes', ['only' => ['index']]);
          });
      };
      PHP
  end

  it "reports WordPress REST and AJAX lines" do
    expected = ["GET /wp-admin/admin-ajax.php?action=save L6", "GET /wp-json/p/v1/items L3",
                "POST /wp-admin/admin-ajax.php?action=save L6"]
    php_route_lines(Analyzer::Php::Wordpress.new(options), "wp-content/plugins/p/p.php", <<-PHP).should eq(expected)
      <?php
      add_action('rest_api_init', function () {
          register_rest_route('p/v1', '/items', array('methods' => 'GET'));
      });

      add_action('wp_ajax_save', 'p_save');
      PHP
  end

  it "reports Yii urlManager rule and action lines" do
    php_route_lines(Analyzer::Php::Yii.new(options), "config/web.php", <<-PHP).should eq(["GET /about L4", "POST /api/posts L5"])
      <?php
      return ['components' => ['urlManager' => ['rules' => [

          'about' => 'site/about',
          'POST api/posts' => 'post/create',
      ]]]];
      PHP

    php_route_lines(Analyzer::Php::Yii.new(options), "controllers/SiteController.php", <<-PHP).should eq(["GET /site/index L6"])
      <?php
      namespace app;

      class SiteController extends Controller
      {
          public function actionIndex() {}
      }
      PHP
  end

  it "reports Laminas config route lines, child routes too" do
    php_route_lines(Analyzer::Php::Laminas.new(options), "module/App/config/module.config.php", <<-PHP).should eq(["GET /blog L4", "GET /blog/feed L9"])
      <?php
      return ['router' => [
          'routes' => [
              'blog' => [
                  'type' => Literal::class,
                  'options' => ['route' => '/blog'],
                  'may_terminate' => true,
                  'child_routes' => [
                      'feed' => [
                          'type' => Literal::class,
                          'options' => ['route' => '/feed'],
                      ],
                  ],
              ],
          ],
      ]];
      PHP
  end
end
