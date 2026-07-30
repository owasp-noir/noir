require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/slim"
require "../../../src/analyzer/analyzers/php/laminas"
require "../../../src/analyzer/analyzers/php/cakephp"

# Every PHP analyzer is fed every `.php` file in the scan, so each one's
# relevance gate is the only thing keeping it off the other frameworks' route
# files. These harnesses expose the gates so the cross-framework rules can be
# pinned without running a full multi-framework scan.
class SlimRelevanceHarness < Analyzer::Php::Slim
  def relevant?(content : String) : Bool
    slim_relevant?(content)
  end
end

class LaminasRelevanceHarness < Analyzer::Php::Laminas
  def relevant?(path : String, content : String) : Bool
    laminas_relevant?(path, content)
  end
end

# CakePHP gates on the `config/routes.php` path, which Hyperf uses too.
class CakePhpHyperfHarness < Analyzer::Php::CakePHP
  def hyperf?(content : String) : Bool
    content.matches?(HYPERF_MARKER_RE)
  end
end

private CODEIGNITER_ROUTES = <<-PHP
  <?php
  $routes->get('users/(:num)', 'UserController::show/$1');
  $routes->put('users/(:num)', 'UserController::update/$1');
  $routes->group('tenant/(:num)', function ($routes) {
      $routes->get('billing', 'Billing::index');
  });
  PHP

private CAKEPHP_ROUTES = <<-PHP
  <?php
  $routes->scope('/', function (RouteBuilder $builder) {
      $builder->get('/status', ['controller' => 'Api', 'action' => 'status']);
      $builder->get('/users', ['controller' => 'Users', 'action' => 'index']);
  });
  PHP

private LUMEN_ROUTES = <<-PHP
  <?php
  $router->get('/health', 'HealthController@index');
  $router->put('/users/{id}', 'UserController@update');
  PHP

private MEZZIO_ROUTES = <<-PHP
  <?php
  use Mezzio\\Application;

  return function (Application $app) {
      $app->get('/docs/commented', DocsHandler::class, 'docs');
      $app->delete('/api/users/{id}', DeleteUserHandler::class);
  };
  PHP

private HYPERF_ROUTES = <<-'PHP'
  <?php
  use Hyperf\\HttpServer\\Router\\Router;

  Router::get('/items/{itemId}', [App\\Controller\\ItemController::class, 'show']);
  Router::addGroup('/api/v1', function () {
      Router::get('/me', [App\\Controller\\AuthController::class, 'me']);
  });
  PHP

describe "PHP cross-framework relevance gates" do
  describe Analyzer::Php::Slim do
    harness = SlimRelevanceHarness.new(create_test_options)

    it "claims a file that names Slim" do
      harness.relevant?(<<-PHP).should be_true
        <?php
        use Slim\\Factory\\AppFactory;
        $app = AppFactory::create();
        $app->get('/status', function ($req, $res) { return $res; });
        PHP
    end

    it "still claims a marker-less file registering on a Slim-shaped handle" do
      # Slim 3-era `routes.php` files carry no `Slim\` reference at all; the
      # fallback exists for them and must keep working.
      harness.relevant?(<<-PHP).should be_true
        <?php
        $app->get('/status', function ($req, $res) { return $res; });
        PHP
    end

    it "does not claim another framework's route file" do
      # `$routes` is CodeIgniter/CakePHP, `$builder` is CakePHP's RouteBuilder,
      # `$router` is Lumen. Pre-fix each of these produced phantom Slim routes
      # in any repo holding more than one PHP framework — CodeIgniter's
      # `users/(:num)` was reported verbatim as a Slim route.
      harness.relevant?(CODEIGNITER_ROUTES).should be_false
      harness.relevant?(CAKEPHP_ROUTES).should be_false
      harness.relevant?(LUMEN_ROUTES).should be_false
    end

    it "does not claim a Mezzio route table" do
      # Mezzio registers on `$app->get('/x', Handler::class)` — the same
      # expression Slim uses — so Slim reported Mezzio's routes as its own.
      # `Laminas\\` is deliberately not a disqualifier: Slim apps pull in
      # `Laminas\\Diactoros` for PSR-7 all the time.
      harness.relevant?(MEZZIO_ROUTES).should be_false
      harness.relevant?(<<-'PHP').should be_true
        <?php
        use Slim\\Factory\\AppFactory;
        use Laminas\\Diactoros\\ResponseFactory;

        $app = AppFactory::create();
        $app->get('/status', function ($req, $res) { return $res; });
        PHP
    end
  end

  describe Analyzer::Php::CakePHP do
    harness = CakePhpHyperfHarness.new(create_test_options)

    it "recognizes a Hyperf route table so it can step aside" do
      # Hyperf keeps its routes at `config/routes.php` too and writes
      # `Router::get(...)`, a call shape CakePHP 3 also used.
      harness.hyperf?(HYPERF_ROUTES).should be_true
      harness.hyperf?(CAKEPHP_ROUTES).should be_false
    end
  end

  describe Analyzer::Php::Laminas do
    harness = LaminasRelevanceHarness.new(create_test_options)

    it "claims a file that names Laminas/Zend/Mezzio" do
      harness.relevant?("/app/config/routes.php", <<-PHP).should be_true
        <?php
        use Mezzio\\Application;
        return function (Application $app) {
            $app->get('/api/ping', PingHandler::class, 'api.ping');
        };
        PHP
    end

    it "claims a config file carrying a router array" do
      harness.relevant?("/app/config/autoload/routes.global.php", <<-PHP).should be_true
        <?php
        return ['router' => ['routes' => []]];
        PHP
    end

    it "no longer claims any file that merely calls ->get with a string" do
      # The old catch-all branch treated `->get('…')` as a Laminas signal. It
      # is a "some PHP code calls a getter with a string" signal, and it
      # claimed other frameworks' route files (16 phantom endpoints across the
      # fixture tree) plus ordinary config reads.
      harness.relevant?("/app/config/Routes.php", CODEIGNITER_ROUTES).should be_false
      harness.relevant?("/app/config/routes.php", CAKEPHP_ROUTES).should be_false
      harness.relevant?("/app/routes/web.php", LUMEN_ROUTES).should be_false
      harness.relevant?("/app/src/Service.php", <<-PHP).should be_false
        <?php
        class Service {
            public function boot() { return $this->config->get('db.host'); }
        }
        PHP
    end
  end
end
