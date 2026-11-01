require "file_utils"
require "../../func_spec.cr"

# A refusal is an auth guard only if a guest reaches it. Nested / conditional
# guest pass-throughs must not cancel a later guest refusal; read-only lookups
# (not stores, services or inserts) may precede a policy check; `-es` plurals.
describe "Laravel guest gates, policy lookups and plural parameters", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints
  end

  it "keeps guards behind a conditional guest pass-through" do
    endpoints = scan.call("./spec/functional_test/fixtures/php/laravel_guest_gates/")
    guards = ->(url : String) do
      ep = endpoints.find! { |e| e.url == url }
      ep.ai_context.try(&.guards.map(&.name)) || [] of String
    end

    guards.call("/mw/nested").should eq(["Laravel NestedPass middleware"])
    guards.call("/mw/apionly").should eq(["Laravel ApiOnlyPass middleware"])
    guards.call("/mw/config").should eq(["Laravel ConfigGuestPass middleware (an environment or config check decides; a setting can make it public)"])
    # `['api.ip', 'auth:sanctum']`: the named auth alias is the guard.
    guards.call("/mw/alias").should eq(["Laravel auth:sanctum middleware"])

    # Side effects before `authorize` are not lookups.
    %w[/p/store/{id} /p/service/{id} /p/insert /p/mail/{id}].each do |url|
      guards.call(url).select(&.includes?("policy")).should be_empty
    end
    guards.call("/p/multi/{id}").any?(&.includes?("policy")).should be_true

    # A guest pass-through inside a switch, loop, catch, closure or else
    # branch is not unconditional: the later refusal still guards. Only a
    # top-level one (or in a `try` body) cancels it.
    %w[SwitchPass ForeachPass WhilePass CatchPass ClosurePass ElsePass ElseIfPass ElseIfSpaced NoBraceNested].each do |name|
      guards.call("/mw2/#{name}").should eq(["Laravel #{name} middleware"])
    end
    %w[TopPass TryPass MatchPass SameCondTwice].each do |name|
      guards.call("/mw2/#{name}").should be_empty
    end

    # Reads by exact name only: `*OrCreate`, `getOr*`, `load*And*`, namespaced,
    # upper-case or variable function calls stop the lookup walk.
    %w[firstOrCreate getOrCreate resolveCharge loadMark findOrNewSave withoutEvents nsFunc ucFunc varCall whereUpdate getThenPut].each do |name|
      guards.call("/p2/#{name}/{id}").select(&.includes?("policy")).should be_empty
    end
    guards.call("/p2/readOk/{id}").any?(&.includes?("policy")).should be_true

    # A zero-argument getter in front of a read that ends the chain is a
    # lookup (snipeit's `parent::getMapObjectType()[$t]::withTrashed()->find`);
    # `getOrCreate()` or a getter with arguments is not.
    guards.call("/p3/getterRead/{t}/{id}").any?(&.includes?("policy")).should be_true
    guards.call("/p3/getterOrCreate/{id}").select(&.includes?("policy")).should be_empty
    guards.call("/p3/getterWithArgs/{id}").select(&.includes?("policy")).should be_empty
  end

  it "analyzes a middleware with many pass-through blocks and refusals in linear time" do
    # n guest pass-throughs inside loops, then n refusals: every refusal used to
    # rescan the body for every earlier pass-through (cubic overall).
    time_for = ->(n : Int32) do
      dir = File.tempname("laravel_mw_scaling")
      Dir.mkdir_p(File.join(dir, "app/Http/Middleware"))
      Dir.mkdir_p(File.join(dir, "routes"))
      File.write(File.join(dir, "composer.json"), %({"require":{"laravel/framework":"^10.0"},"autoload":{"psr-4":{"App\\\\":"app/"}}}))
      File.write(File.join(dir, "artisan"), "")
      File.write(File.join(dir, "routes/web.php"), "<?php\nuse Illuminate\\Support\\Facades\\Route;\nRoute::get('big', fn() => 1)->middleware(\\App\\Http\\Middleware\\Big::class);\n")
      File.write(File.join(dir, "app/Http/Middleware/Big.php"), String.build do |io|
        io << "<?php\nnamespace App\\Http\\Middleware;\nuse Closure;\nclass Big\n{\n    public function handle($request, Closure $next)\n    {\n"
        n.times { io << "        foreach ($a as $b) { if (! $request->user()) { return $next($request); } }\n" }
        n.times { |i| io << "        if ($request->user() && $request->user()->f#{i}) { abort(403); }\n" }
        io << "        return $next($request);\n    }\n}\n"
      end)
      begin
        CodeLocator.instance.clear_all
        Time.measure { scan.call(dir) }
      ensure
        FileUtils.rm_rf(dir)
      end
    end
    time_for.call(20) # warm up
    small = time_for.call(200).total_seconds
    large = time_for.call(800).total_seconds
    # Linear is ~4x; the cubic walk was ~50x. Generous bound against noise.
    (large / Math.max(small, 0.01)).should be < 8
  end

  it "singularizes -es plurals like Laravel" do
    urls = scan.call("./spec/functional_test/fixtures/php/laravel_guest_gates/").map(&.url)
    ["/sizes/{size}", "/prizes/{prize}", "/caches/{cache}", "/buses/{bus}", "/houses/{house}", "/licenses/{license}", "/boxes/{box}"].each do |url|
      urls.should contain(url)
    end
  end

  it "keeps CakePHP nested resource ids" do
    urls = scan.call("./spec/functional_test/fixtures/php/cakephp_es_singulars/").map(&.url)
    urls.should contain("/sizes/{size_id}/stocks")
    urls.should contain("/caches/{cache_id}/keys")
    urls.should contain("/licenses/{license_id}/seats")
  end
end
