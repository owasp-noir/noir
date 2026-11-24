require "file_utils"
require "../../spec_helper"
require "../../../src/models/noir"

private KERNEL = <<-'PHP'
  <?php
  namespace App\Http;
  use Illuminate\Foundation\Http\Kernel as HttpKernel;
  class Kernel extends HttpKernel
  {
      protected $middlewareGroups = [
          'web' => [ \Illuminate\Session\Middleware\StartSession::class ],
          'admin' => [ 'auth', 'role:admin' ],
      ];
      protected $middlewareAliases = [
          'role' => \Spatie\Permission\Middleware\RoleMiddleware::class,
          'role_or_permission' => \Spatie\Permission\Middleware\RoleOrPermissionMiddleware::class,
          'abilities' => \Laravel\Sanctum\Http\Middleware\CheckAbilities::class,
          'scope' => \Laravel\Passport\Http\Middleware\CheckForAnyScope::class,
      ];
  }
  PHP

private ROUTES = <<-'PHP'
  <?php
  use Illuminate\Support\Facades\Route;

  Route::get('/roles', fn () => 1)->middleware(['auth', 'role:admin|editor,api']);
  Route::get('/abilities', fn () => 1)->middleware(['auth:sanctum', 'abilities:read,write']);
  Route::get('/any-scope', fn () => 1)->middleware(['auth:api', 'scope:a,b']);
  Route::get('/either', fn () => 1)->middleware(['auth', 'role_or_permission:admin|edit']);
  Route::get('/constant', fn () => 1)->middleware(['auth', 'role:' . Role::ADMIN]);
  Route::get('/only-role', fn () => 1)->middleware('role:admin');
  Route::get('/guest-too', fn () => 1)->middleware(['auth', 'guest']);
  Route::middleware('admin')->group(function () {
      Route::get('/group', fn () => 1);
      Route::get('/group-out', fn () => 1)->withoutMiddleware('role:admin');
  });
  Route::middleware(['auth', 'can:edit'])->group(function () {
      Route::get('/can-out', fn () => 1)->withoutMiddleware('can:edit');
  });
  Route::put('/posts/{post}', function (Post $post) {
      $this->authorize('update', $post);
      return $post;
  });
  PHP

# Scanned once, on first use rather than when the suite loads.
private SCANNED = [] of Endpoint

private def scanned : Array(Endpoint)
  SCANNED.concat(scan_laravel) if SCANNED.empty?
  SCANNED
end

private def scan_laravel : Array(Endpoint)
  CodeLocator.instance.clear_all
  root = File.tempname("laravel_requires")
  begin
    FileUtils.mkdir_p(File.join(root, "app/Http"))
    FileUtils.mkdir_p(File.join(root, "routes"))
    File.write(File.join(root, "composer.json"), %({"require": {"laravel/framework": "^10.0"}}))
    File.write(File.join(root, "artisan"), "#!/usr/bin/env php\n<?php\n")
    File.write(File.join(root, "app/Http/Kernel.php"), KERNEL)
    File.write(File.join(root, "routes/web.php"), ROUTES)
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    runner.endpoints
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(root)
  end
end

# {tag name => its clauses}, each clause as its atoms.
private def requires_of(url : String) : Hash(String, Array(Array(String)))
  endpoint = scanned.find! { |ep| ep.url == url }
  endpoint.tags.select(&.tagger.==("php_auth")).to_h do |tag|
    {tag.name, tag.requires.not_nil!.map(&.any_of.map(&.to_s))}
  end
end

describe "Laravel route requires" do
  it "reads Spatie roles as one any-of clause, without the guard argument" do
    requires_of("/roles").should eq({"auth" => [["authenticated"], ["role:admin", "role:editor"]]})
  end

  it "reads Sanctum abilities as all-of and Passport scope as any-of" do
    requires_of("/abilities").should eq({"auth" => [["authenticated"], ["scope:read"], ["scope:write"]]})
    requires_of("/any-scope").should eq({"auth" => [["authenticated"], ["scope:a", "scope:b"]]})
  end

  it "keeps role_or_permission, a truncated parameter and guest unread" do
    requires_of("/either").should eq({"auth" => [["authenticated"], ["unresolved"]]})
    requires_of("/constant").should eq({"auth" => [["authenticated"], ["unresolved"]]})
    requires_of("/guest-too").should eq({"auth" => [["authenticated"], ["unresolved"]]})
  end

  it "adds no tag where main adds none" do
    requires_of("/only-role").should be_empty
  end

  it "reads a group's members and lifts the member a route withdraws" do
    requires_of("/group").should eq({"auth" => [["authenticated"], ["role:admin"]]})
    requires_of("/group-out").should eq({"auth" => [["authenticated"], ["role:admin", "unresolved"]]})
  end

  it "puts can: on the authz tag and lifts it when withdrawn" do
    requires_of("/can-out").should eq({"auth" => [["authenticated"]], "authz" => [["permission:edit", "unresolved"]]})
  end

  it "reads a handler's literal policy call as the ability" do
    requires_of("/posts/{post}").should eq({"auth" => [["permission:update"]]})
  end
end
