require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/php/laravel"

describe Analyzer::Php::Laravel do
  options = create_test_options
  analyzer = Analyzer::Php::Laravel.new(options)

  describe "HTTP QUERY and Route methods" do
    it "detects Route::query routes" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::query('/search', [SearchController::class, 'index']);
        Route::query('/items/{id}/details', function ($id) {
            return response()->json(['id' => $id]);
        });
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      endpoints.size.should eq(2)

      ep1 = endpoints.find { |e| e.url == "/search" }
      ep1.should_not be_nil
      if ep1
        ep1.method.should eq("QUERY")
        ep1.params.should be_empty
      end

      ep2 = endpoints.find { |e| e.url == "/items/{id}/details" }
      ep2.should_not be_nil
      if ep2
        ep2.method.should eq("QUERY")
        ep2.params.size.should eq(1)
        ep2.params[0].name.should eq("id")
        ep2.params[0].param_type.should eq("path")
      end

      File.delete(temp_file)
      Dir.delete(routes_dir)
      Dir.delete(temp_dir)
    end

    it "detects Route::match with QUERY in array" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::match(['get', 'query'], '/filter', function () {
            return response()->json([]);
        });
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      endpoints.size.should eq(2)
      methods = endpoints.map(&.method).sort!
      methods.should eq(["GET", "QUERY"])
      endpoints.all? { |e| e.url == "/filter" }.should be_true

      File.delete(temp_file)
      Dir.delete(routes_dir)
      Dir.delete(temp_dir)
    end

    it "detects Route::addRoute with QUERY as string or array" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::addRoute('QUERY', '/advanced-search', function () {
            return response()->json([]);
        });
        Route::addRoute(['GET', 'QUERY'], '/multi-search', function () {
            return response()->json([]);
        });
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      endpoints.size.should eq(3)

      adv = endpoints.find { |e| e.url == "/advanced-search" }
      adv.should_not be_nil
      adv.try(&.method).should eq("QUERY")

      multi = endpoints.select { |e| e.url == "/multi-search" }
      multi.size.should eq(2)
      multi.map(&.method).sort!.should eq(["GET", "QUERY"])

      File.delete(temp_file)
      Dir.delete(routes_dir)
      Dir.delete(temp_dir)
    end

    it "detects chained Route::query and chained Route::addRoute" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::middleware('auth')->query('/secure-search', function () {
            return response()->json([]);
        });
        Route::query('/search-chained', function () {
            return response()->json([]);
        })->middleware('auth');
        Route::prefix('v1')->middleware('auth')->addRoute('QUERY', '/v1-search', function () {
            return response()->json([]);
        });
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      endpoints.size.should eq(3)

      ep1 = endpoints.find { |e| e.url == "/secure-search" }
      ep1.should_not be_nil
      ep1.try(&.method).should eq("QUERY")

      ep2 = endpoints.find { |e| e.url == "/search-chained" }
      ep2.should_not be_nil
      ep2.try(&.method).should eq("QUERY")

      ep3 = endpoints.find { |e| e.url == "/v1/v1-search" }
      ep3.should_not be_nil
      ep3.try(&.method).should eq("QUERY")

      File.delete(temp_file)
      Dir.delete(routes_dir)
      Dir.delete(temp_dir)
    end

    it "detects Route::query inside route groups" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::prefix('api/v2')->group(function () {
            Route::query('/products', function () {
                return response()->json([]);
            });
            Route::match(['get', 'query'], '/categories', function () {
                return response()->json([]);
            });
        });
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      endpoints.size.should eq(3)

      ep1 = endpoints.find { |e| e.url == "/api/v2/products" }
      ep1.should_not be_nil
      ep1.try(&.method).should eq("QUERY")

      cats = endpoints.select { |e| e.url == "/api/v2/categories" }
      cats.size.should eq(2)
      cats.map(&.method).sort!.should eq(["GET", "QUERY"])

      File.delete(temp_file)
      Dir.delete(routes_dir)
      Dir.delete(temp_dir)
    end

    it "does not include QUERY in Route::any fan-out" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::any('/wildcard', function () {
            return response()->json([]);
        });
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      methods = endpoints.map(&.method)
      methods.should_not contain("QUERY")
      methods.sort!.should eq(["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"])

      File.delete(temp_file)
      Dir.delete(routes_dir)
      Dir.delete(temp_dir)
    end

    it "detects controller methods with #[Route] attribute using QUERY" do
      temp_dir = File.tempname("laravel_test")
      controller_dir = File.join(temp_dir, "app", "Http", "Controllers")
      Dir.mkdir_p(controller_dir)
      temp_file = File.join(controller_dir, "SearchController.php")

      File.write(temp_file, <<-'PHP')
        <?php
        namespace App\Http\Controllers;

        class SearchController
        {
            #[Route('/search/attr-array', methods: ['QUERY'])]
            public function searchArray()
            {
                return response()->json([]);
            }

            #[Route('/search/attr-string', methods: 'QUERY')]
            public function searchString()
            {
                return response()->json([]);
            }
        }
        PHP

      endpoints = analyzer.analyze_file(temp_file)
      endpoints.size.should eq(2)

      ep1 = endpoints.find { |e| e.url == "/search/attr-array" }
      ep1.should_not be_nil
      ep1.try(&.method).should eq("QUERY")

      ep2 = endpoints.find { |e| e.url == "/search/attr-string" }
      ep2.should_not be_nil
      ep2.try(&.method).should eq("QUERY")

      File.delete(temp_file)
      FileUtils.rm_rf(temp_dir)
    end
  end

  describe "array resources and singletons" do
    it "expands apiResources/resources entries and singleton routes" do
      temp_dir = File.tempname("laravel_test")
      routes_dir = File.join(temp_dir, "routes")
      Dir.mkdir_p(routes_dir)
      temp_file = File.join(routes_dir, "web.php")

      File.write(temp_file, <<-'PHP')
        <?php
        use Illuminate\Support\Facades\Route;

        Route::apiResources(['photos' => PhotoController::class]);
        Route::resources([
            'tags' => TagController::class,
        ], ['except' => ['create', 'edit']]);
        Route::singleton('profile', ProfileController::class);
        Route::apiSingleton('settings', SettingsController::class)->creatable();
        Route::resource('items', ItemController::class, ['only' => ['index']]);
        PHP

      begin
        # The analyzer leaves the leading `/` to the optimizer.
        found = analyzer.analyze_file(temp_file).map { |e| "#{e.method} /#{e.url.lchop('/')} #{e.details.code_paths.first.line}" }
        found.sort.should eq([
          "DELETE /photos/{photo} 4", "GET /photos 4", "GET /photos/{photo} 4",
          "PATCH /photos/{photo} 4", "POST /photos 4", "PUT /photos/{photo} 4",
          "DELETE /tags/{tag} 6", "GET /tags 6", "GET /tags/{tag} 6",
          "PATCH /tags/{tag} 6", "POST /tags 6", "PUT /tags/{tag} 6",
          "GET /profile 8", "GET /profile/edit 8", "PATCH /profile 8", "PUT /profile 8",
          "DELETE /settings 9", "GET /settings 9", "PATCH /settings 9",
          "POST /settings 9", "PUT /settings 9",
          "GET /items 10",
        ].sort)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end
  end

  it "resolves many routes into one large controller in linear time" do
    # Ratio, not wall clock: CI runners vary. 4x the routes must cost well
    # under the 16x a per-route controller re-parse would.
    scan = ->(count : Int32) do
      temp_dir = File.tempname("laravel_test")
      begin
        Dir.mkdir_p(File.join(temp_dir, "routes"))
        Dir.mkdir_p(File.join(temp_dir, "app", "Http", "Controllers"))
        Dir.mkdir_p(File.join(temp_dir, "app", "Http", "Requests"))
        routes_file = File.join(temp_dir, "routes", "web.php")
        File.write(routes_file, String.build do |io|
          io << "<?php\nuse App\\Http\\Controllers\\UserController;\n"
          count.times { |i| io << "Route::post('/u#{i}', [UserController::class, 'm#{i}']);\n" }
        end)
        File.write(File.join(temp_dir, "app", "Http", "Controllers", "UserController.php"), String.build do |io|
          io << "<?php\nnamespace App\\Http\\Controllers;\nuse App\\Http\\Requests\\StoreUserRequest;\nclass UserController\n{\n"
          count.times { |i| io << "    public function m#{i}(StoreUserRequest $request)\n    {\n        return $request->input('a#{i}');\n    }\n" }
          io << "}\n"
        end)
        File.write(File.join(temp_dir, "app", "Http", "Requests", "StoreUserRequest.php"),
          "<?php\nclass StoreUserRequest { public function rules() { return ['name' => 'required']; } }\n")

        endpoints = [] of Endpoint
        elapsed = Time.measure { endpoints = Analyzer::Php::Laravel.new(options).analyze_file(routes_file) }
        endpoints.size.should eq(count)
        last = endpoints.find!(&.url.==("/u#{count - 1}"))
        last.params.map(&.name).should eq(["a#{count - 1}", "name"])
        elapsed
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    small = scan.call(500)
    large = scan.call(2000)
    large.should be < (small * 8 + 500.milliseconds)
  end
end
