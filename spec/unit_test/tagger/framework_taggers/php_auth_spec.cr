require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "PhpAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/php/laravel_auth", __DIR__)
  controller_path = "#{fixture_base}/app/Http/Controllers/PostController.php"
  public_path = "#{fixture_base}/app/Http/Controllers/PublicController.php"

  # PostController.php line reference:
  # 10:     $this->middleware('auth');
  # 14:   public function index()
  # 19:   public function store(Request $request)
  # 21:     $this->authorize('create', Post::class);

  it "detects $this->middleware('auth') in constructor" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "php_laravel"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("php_auth")
    endpoint.tags[0].description.should contain("auth")
  end

  it "detects $this->authorize in action body" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 19))
    details.technology = "php_laravel"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end

  it "does not attribute the next route's middleware to the route above it" do
    tmpdir = File.tempname("php_adjacent_routes")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "web.php")
    File.write(routes, [
      "<?php",
      "",
      "Route::get('/public', function () { return 'public'; });",
      "Route::get('/me', function () { return 'me'; })->middleware('auth');",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    public_details = Details.new(PathInfo.new(routes, 3))
    public_details.technology = "php_laravel"
    public_endpoint = Endpoint.new("/public", "GET", [] of Param, public_details)

    me_details = Details.new(PathInfo.new(routes, 4))
    me_details.technology = "php_laravel"
    me_endpoint = Endpoint.new("/me", "GET", [] of Param, me_details)

    PhpAuthTagger.new(noir_options).perform([public_endpoint, me_endpoint])

    public_endpoint.tags.empty?.should be_true
    me_endpoint.tags.empty?.should be_false
    me_endpoint.tags[0].description.should contain("Laravel auth middleware")

    FileUtils.rm_rf(tmpdir)
  end

  it "does not sweep the next method's auth check into this action's body" do
    tmpdir = File.tempname("php_method_body")
    Dir.mkdir_p(tmpdir)
    controller = File.join(tmpdir, "ReportController.php")
    File.write(controller, [
      "<?php",                                     # 1
      "",                                          # 2
      "class ReportController extends Controller", # 3
      "{",                                         # 4
      "    public function publicIndex()",         # 5
      "    {",                                     # 6
      "        return response()->json(['ok' => true]);",
      "    }",                        # 8
      "",                             # 9
      "    public function secret()", # 10
      "    {",                        # 11
      "        $this->authorize('view', Report::class);",
      "    }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    public_details = Details.new(PathInfo.new(controller, 5))
    public_details.technology = "php_laravel"
    public_endpoint = Endpoint.new("/reports/public", "GET", [] of Param, public_details)

    secret_details = Details.new(PathInfo.new(controller, 10))
    secret_details.technology = "php_laravel"
    secret_endpoint = Endpoint.new("/reports/secret", "GET", [] of Param, secret_details)

    PhpAuthTagger.new(noir_options).perform([public_endpoint, secret_endpoint])

    public_endpoint.tags.empty?.should be_true
    secret_endpoint.tags.empty?.should be_false
    secret_endpoint.tags[0].description.should contain("Policy authorization")

    FileUtils.rm_rf(tmpdir)
  end

  it "does not tag public controller" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(public_path, 8))
    details.technology = "php_laravel"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end

# Light coverage for newly added PHP targets (Slim, Yii, CodeIgniter)
describe "PhpAuthTagger (expanded targets)" do
  slim_base = File.expand_path("../../../functional_test/fixtures/php/slim", __DIR__)
  slim_path = "#{slim_base}/index.php"

  it "runs without error on php_slim technology" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(slim_base)

    # Line 28 in slim fixture has X-Auth-Token header access (manual auth pattern)
    details = Details.new(PathInfo.new(slim_path, 28))
    details.technology = "php_slim"
    endpoint = Endpoint.new("/users/{id}", "GET", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    # We don't assert a tag (fixture has manual header read, not strong declarative auth),
    # but the tagger must not crash and must accept the tech.
    true.should be_true
  end

  it "runs without error on php_yii and php_codeigniter technologies" do
    noir_options = create_test_options
    # Reuse slim dir as base (no real Yii/CI files needed for smoke test)
    noir_options["base"] = YAML::Any.new(slim_base)

    ["php_yii", "php_codeigniter"].each do |tech|
      details = Details.new(PathInfo.new(slim_path, 10))
      details.technology = tech
      endpoint = Endpoint.new("/test", "GET", [] of Param, details)

      tagger = PhpAuthTagger.new(noir_options)
      # Should not raise
      tagger.perform([endpoint])
    end

    true.should be_true
  end

  describe "session user guard (regression for never-match session pattern)" do
    it "detects a guarded $_SESSION['user'] access in the handler body" do
      tmpdir = File.tempname("php_session_guard")
      Dir.mkdir_p(tmpdir)
      file = File.join(tmpdir, "handler.php")
      File.write(file, [
        "<?php",
        "function dashboard() {",
        "    if (!isset($_SESSION['user_id'])) { header('Location: /login'); exit; }",
        "    echo 'secret';",
        "}",
      ].join("\n"))

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(file, 2))
      details.technology = "php_pure"
      endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

      PhpAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags.empty?.should be_false
      endpoint.tags[0].description.should contain("session user guard")

      FileUtils.rm_rf(tmpdir)
    end

    it "does not tag a bare session_start() bootstrap" do
      tmpdir = File.tempname("php_session_bare")
      Dir.mkdir_p(tmpdir)
      file = File.join(tmpdir, "public.php")
      File.write(file, [
        "<?php",
        "function home() {",
        "    session_start();",
        "    echo 'welcome';",
        "}",
      ].join("\n"))

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(file, 2))
      details.technology = "php_pure"
      endpoint = Endpoint.new("/", "GET", [] of Param, details)

      PhpAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags.empty?.should be_true

      FileUtils.rm_rf(tmpdir)
    end
  end

  it "tags every route inside a Laravel middleware group, not only the first" do
    tmpdir = File.tempname("php_group_auth")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "web.php")
    File.write(routes, <<-PHP)
      <?php
      Route::middleware('auth')->group(function () {
          Route::get('/profile', [ProfileController::class, 'edit']);
          Route::patch('/profile', [ProfileController::class, 'update']);
          Route::delete('/profile/{id}', [ProfileController::class, 'destroy']);
      });

      Route::middleware('guest')->group(function () {
          Route::get('register', [RegisteredUserController::class, 'create']);
          Route::post('register', [RegisteredUserController::class, 'store']);
      });

      Route::middleware([
          'auth:sanctum',
          config('jetstream.auth_session'),
      ])->group(function () {
          Route::get('/teams', fn () => view('teams'));
          Route::get('/billing', fn () => view('billing'));
      });

      Route::group(['middleware' => ['web', 'auth']], function () {
          Route::get('/legacy', 'LegacyController@index');
          Route::get('/legacy/2', 'LegacyController@two');
      });

      Route::get('/about', fn () => view('about'));
      PHP

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(routes, line))) }
      protected_lines = [4, 5, 17, 18, 22, 23]
      public_lines = [9, 10, 26]
      endpoints = (protected_lines + public_lines).map { |line| at.call(line) }

      PhpAuthTagger.new(noir_options).perform(endpoints)

      endpoints.each_with_index do |endpoint, i|
        if i < protected_lines.size
          endpoint.tags.map(&.name).should eq(["auth"])
        else
          endpoint.tags.should be_empty
        end
      end
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "reads auth only inside the middleware value, not later group keys" do
    tmpdir = File.tempname("php_group_guest")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "web.php")
    File.write(routes, <<-PHP)
      <?php
      Route::group(['middleware' => 'guest', 'prefix' => 'auth'], function () {
          Route::get('/login', 'LoginController@show');
      });

      Route::middleware(['guest'])->prefix('auth')->group(function () {
          Route::get('/register', 'RegisterController@show');
      });

      Route::middleware(['guest'])->prefix('auth')->get('/forgot', 'ForgotController@show');

      Route::group(['middleware' => ['web', 'auth'], 'prefix' => 'admin'], function () {
          Route::get('/admin', 'AdminController@index');
      });
      PHP

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(routes, line))) }
      endpoints = [3, 7, 10, 13].map { |line| at.call(line) }

      PhpAuthTagger.new(noir_options).perform(endpoints)

      endpoints[0..2].each(&.tags.should(be_empty))
      endpoints[3].tags.map(&.name).should eq(["auth"])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "drops the group tag from a route that calls withoutMiddleware('auth')" do
    tmpdir = File.tempname("php_group_without")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "web.php")
    File.write(routes, <<-PHP)
      <?php
      Route::middleware('auth')->group(function () {
          Route::get('/help', function () { return view('help'); })->withoutMiddleware('auth');
          Route::get('/dashboard', function () { return view('dashboard'); });
          Route::get('/faq', function () {
              return view('faq');
          })->withoutMiddleware(['auth']);
          Route::get('/settings', function () { return view('settings'); });
      });
      PHP

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(routes, line))) }
      help, dashboard, faq, settings = [3, 4, 5, 8].map { |line| at.call(line) }

      PhpAuthTagger.new(noir_options).perform([dashboard, help, faq, settings])

      dashboard.tags.map(&.description).should eq(["Protected by Laravel auth middleware (group)"])
      settings.tags.map(&.description).should eq(["Protected by Laravel auth middleware (group)"])
      help.tags.should be_empty
      faq.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "requires identity on CakePHP actions once AuthenticationComponent is loaded, except the unauthenticated ones" do
    tmpdir = File.tempname("php_cake_authn")
    controllers = File.join(tmpdir, "src", "Controller")
    Dir.mkdir_p(File.join(controllers, "Admin"))
    Dir.mkdir_p(File.join(tmpdir, "config"))
    routes = File.join(tmpdir, "config", "routes.php")
    File.write(routes, <<-'PHP')
      <?php
      use Cake\Routing\RouteBuilder;
      return function (RouteBuilder $routes): void {
          $routes->scope('/', function (RouteBuilder $builder): void {
              $builder->connect('/login', ['controller' => 'Users', 'action' => 'login']);
              $builder->connect('/articles', ['controller' => 'Articles', 'action' => 'index']);
              $builder->connect('/articles/add', ['controller' => 'Articles', 'action' => 'add']);
              $builder->connect('/articles/{id}', 'Articles::view');
              $builder->connect('/admin/stats', ['prefix' => 'Admin', 'controller' => 'Stats', 'action' => 'index']);
              $builder->connect('/health', ['controller' => 'Health', 'action' => 'index']);
          });
      };
      PHP
    File.write(File.join(controllers, "AppController.php"), <<-'PHP')
      <?php
      namespace App\Controller;
      use Cake\Controller\Controller;
      class AppController extends Controller
      {
          public function initialize(): void
          {
              parent::initialize();
              $this->loadComponent('Authentication.Authentication');
          }
      }
      PHP
    File.write(File.join(controllers, "UsersController.php"), <<-'PHP')
      <?php
      namespace App\Controller;
      class UsersController extends AppController
      {
          public function beforeFilter(\Cake\Event\EventInterface $event)
          {
              parent::beforeFilter($event);
              $this->Authentication->addUnauthenticatedActions(['login', 'add']);
          }
          public function login()
          {
              $result = $this->Authentication->getResult();
          }
      }
      PHP
    File.write(File.join(controllers, "ArticlesController.php"), <<-'PHP')
      <?php
      namespace App\Controller;
      class ArticlesController extends AppController
      {
          public function beforeFilter(\Cake\Event\EventInterface $event)
          {
              parent::beforeFilter($event);
              $this->Authentication->allowUnauthenticated(['index']);
          }
          public function index() {}
          public function add() {}
          public function view($id) {}
      }
      PHP
    File.write(File.join(controllers, "Admin", "StatsController.php"), <<-'PHP')
      <?php
      namespace App\Controller\Admin;
      use App\Controller\AppController;
      class StatsController extends AppController
      {
          public function index() {}
      }
      PHP
    File.write(File.join(controllers, "HealthController.php"), <<-'PHP')
      <?php
      namespace App\Controller;
      use Cake\Controller\Controller;
      class HealthController extends Controller
      {
          public function index() {}
      }
      PHP

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) do
        details = Details.new(PathInfo.new(routes, line))
        details.technology = "php_cakephp"
        Endpoint.new("/#{line}", "GET", [] of Param, details)
      end
      endpoints = {login: 5, index: 6, add: 7, view: 8, admin: 9, health: 10}.to_h.transform_values { |line| at.call(line) }

      PhpAuthTagger.new(noir_options).perform(endpoints.values)

      endpoints.select { |_, endpoint| endpoint.tags.any?(&.name.== "auth") }.keys.should eq([:add, :view, :admin])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "leaves CakePHP actions untagged when identity is optional, the exempt list is unreadable or the component is commented out" do
    tmpdir = File.tempname("php_cake_edges")
    files = {
      "config/routes.php" => <<-PHP,
        <?php
        return function (RouteBuilder $routes): void {
            $routes->connect('/pages', ['controller' => 'Pages', 'action' => 'display']);
            $routes->connect('/open', ['controller' => 'Open', 'action' => 'index']);
            $routes->connect('/status', ['controller' => 'Status', 'action' => 'index']);
            $routes->prefix('Api', function (RouteBuilder $builder): void {
                $builder->connect('/articles', ['controller' => 'Articles', 'action' => 'add']);
            });
            $routes->connect('/articles', ['controller' => 'Articles', 'action' => 'add']);
        };
        PHP
      "src/Controller/AppController.php" => <<-PHP,
        <?php
        class AppController extends Controller
        {
            public function initialize(): void
            {
                $this->loadComponent('Authentication.Authentication');
            }
        }
        PHP
      "src/Controller/PagesController.php" => <<-PHP,
        <?php
        class PagesController extends AppController
        {
            protected array $publicActions = ['display'];
            public function beforeFilter($event)
            {
                $this->Authentication->allowUnauthenticated($this->publicActions);
            }
        }
        PHP
      "src/Controller/OpenController.php" => <<-PHP,
        <?php
        class OpenController extends Controller
        {
            public function initialize(): void
            {
                $this->loadComponent('Authentication.Authentication', ['requireIdentity' => false]);
            }
        }
        PHP
      "src/Controller/StatusController.php" => <<-PHP,
        <?php
        class StatusController extends AppController
        {
            public function initialize(): void
            {
                $this->Authentication->setConfig('requireIdentity', false);
            }
        }
        PHP
      "src/Controller/Api/ArticlesController.php" => <<-PHP,
        <?php
        class ArticlesController extends Controller
        {
            public function initialize(): void
            {
                // $this->loadComponent('Authentication.Authentication');
            }
        }
        PHP
      "src/Controller/ArticlesController.php" => <<-PHP,
        <?php
        class ArticlesController extends AppController
        {
        }
        PHP
      "plugins/Blog/config/routes.php" => <<-PHP,
        <?php
        $routes->connect('/blog/posts', ['controller' => 'Posts', 'action' => 'add']);
        PHP
      "plugins/Blog/src/Controller/AppController.php" => <<-'PHP',
        <?php
        class AppController extends \App\Controller\AppController
        {
        }
        PHP
      "plugins/Blog/src/Controller/PostsController.php" => <<-PHP,
        <?php
        class PostsController extends AppController
        {
        }
        PHP
    }
    files.each do |name, body|
      path = File.join(tmpdir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(file : String, line : Int32) do
        details = Details.new(PathInfo.new(File.join(tmpdir, file), line))
        details.technology = "php_cakephp"
        Endpoint.new("/#{line}", "GET", [] of Param, details)
      end
      endpoints = {
        pages: at.call("config/routes.php", 3), open: at.call("config/routes.php", 4),
        status: at.call("config/routes.php", 5), api: at.call("config/routes.php", 7),
        articles: at.call("config/routes.php", 9), plugin: at.call("plugins/Blog/config/routes.php", 2),
      }.to_h

      PhpAuthTagger.new(noir_options).perform(endpoints.values)

      endpoints.select { |_, endpoint| endpoint.tags.any?(&.name.== "auth") }.keys.should eq([:articles, :plugin])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "reads a Yii AccessControl behavior: only/except, then the first rule a guest matches" do
    tmpdir = File.tempname("php_yii_acf")
    Dir.mkdir_p(tmpdir)
    site = File.join(tmpdir, "SiteController.php")
    admin = File.join(tmpdir, "AdminController.php")
    File.write(site, <<-PHP)
      <?php
      class SiteController extends Controller
      {
          public function behaviors()
          {
              return [
                  'access' => [
                      'class' => AccessControl::class,
                      'only' => ['logout', 'signup'],
                      'rules' => [
                          ['actions' => ['signup'], 'allow' => true, 'roles' => ['?']],
                          ['actions' => ['logout'], 'allow' => true, 'roles' => ['@']],
                      ],
                  ],
              ];
          }

          public function actionIndex()
          {
              return $this->render('index');
          }

          public function actionSignup()
          {
              return $this->render('signup');
          }

          public function actionLogout()
          {
              return $this->goHome();
          }
      }
      PHP
    File.write(admin, <<-PHP)
      <?php
      class AdminController extends Controller
      {
          public function behaviors()
          {
              return [
                  'access' => [
                      'class' => AccessControl::class,
                      'except' => ['health'],
                      'rules' => [
                          ['actions' => ['login', 'error'], 'allow' => true],
                          ['actions' => ['list-users', 'index'], 'allow' => true, 'roles' => ['@']],
                      ],
                  ],
              ];
          }

          public function actionLogin() {}

          public function actionListUsers() {}

          public function actionReport() {}

          public function actionHealth() {}
      }
      PHP

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(path : String, line : Int32) do
        details = Details.new(PathInfo.new(path, line))
        details.technology = "php_yii"
        Endpoint.new("/#{line}", "GET", [] of Param, details)
      end
      endpoints = {
        index: at.call(site, 18), signup: at.call(site, 23), logout: at.call(site, 28),
        login: at.call(admin, 18), list_users: at.call(admin, 20), report: at.call(admin, 22), health: at.call(admin, 24),
      }.to_h

      PhpAuthTagger.new(noir_options).perform(endpoints.values)

      # A guest matches no rule for `logout` or `report` (`'@'` is not a guest), so both are denied.
      endpoints.select { |_, endpoint| endpoint.tags.any?(&.name.== "auth") }.keys.should eq([:logout, :list_users, :report])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "skips Yii AccessControl rules it cannot read and reads array() rules and className()" do
    tmpdir = File.tempname("php_yii_edges")
    Dir.mkdir_p(tmpdir)
    files = {
      "RulesController.php" => <<-PHP,
        <?php
        class RulesController extends Controller
        {
            public function behaviors()
            {
                return ['access' => ['class' => AccessControl::class, 'rules' => $this->accessRules()]];
            }
            public function actionView() {}
        }
        PHP
      "LongController.php" => <<-PHP,
        <?php
        class LongController extends Controller
        {
            public function behaviors()
            {
                return array('access' => array('class' => AccessControl::class, 'rules' => array(array('allow' => true, 'actions' => array('page')))));
            }
            public function actionPage() {}
        }
        PHP
      "OldController.php" => <<-PHP,
        <?php
        class OldController extends Controller
        {
            public function behaviors()
            {
                return ['access' => ['class' => AccessControl::className(), 'rules' => [['allow' => true, 'roles' => ['@']]]]];
            }
            public function actionSecret() {}
        }
        PHP
    }
    endpoints = files.map do |name, body|
      path = File.join(tmpdir, name)
      File.write(path, body)
      details = Details.new(PathInfo.new(path, 8))
      details.technology = "php_yii"
      {name, Endpoint.new("/#{name}", "GET", [] of Param, details)}
    end.to_h

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      PhpAuthTagger.new(noir_options).perform(endpoints.values)

      endpoints.select { |_, endpoint| endpoint.tags.any?(&.name.== "auth") }.keys.should eq(["OldController.php"])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
