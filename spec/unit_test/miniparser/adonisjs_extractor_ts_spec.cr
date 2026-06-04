require "spec"
require "../../../src/miniparsers/adonisjs_extractor_ts"

describe Noir::TreeSitterAdonisJsExtractor do
  it "extracts top-level verb routes" do
    source = <<-TS
      Route.get('/', 'HomeController.index')
      Route.post('/login', 'AuthController.login')
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/"},
      {"POST", "/login"},
    ])
  end

  it "fans out .any into the standard verb set" do
    source = <<-TS
      Route.any('/wildcard', 'WildcardController.handle')
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    routes.map(&.verb).sort!.should eq(["DELETE", "GET", "PATCH", "POST", "PUT"])
    routes.map(&.path).uniq!.should eq(["/wildcard"])
  end

  it "applies group prefixes, including nested groups with .prefix" do
    source = <<-TS
      Route.group(() => {
          Route.get('/users', 'UsersController.index')

          Route.group(() => {
              Route.post('/posts', 'PostsController.store')
          }).prefix('/blog').middleware('auth')
      }).prefix('/api/v1')
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/api/v1/users"},
      {"POST", "/api/v1/blog/posts"},
    ].sort)
  end

  it "expands .resource into the five REST API routes" do
    source = <<-TS
      Route.resource('articles', 'ArticlesController').apiOnly()
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/articles"},
      {"POST", "/articles"},
      {"GET", "/articles/:id"},
      {"PUT", "/articles/:id"},
      {"DELETE", "/articles/:id"},
    ].sort)
  end

  it "restricts resource routes with .only" do
    source = <<-TS
      Route.resource('tags', 'TagsController').only(['index', 'show'])
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/tags"},
      {"GET", "/tags/:id"},
    ].sort)
  end

  it "drops actions listed in .except" do
    source = <<-TS
      Route.resource('tags', 'TagsController').except(['destroy', 'update'])
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    # index (GET /tags), store (POST /tags), show (GET /tags/:id) remain.
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/tags"},
      {"GET", "/tags/:id"},
      {"POST", "/tags"},
    ].sort)
  end

  it "handles inline arrow-function handlers" do
    source = <<-TS
      Route.get('/health', () => ({ ok: true }))
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/health"}])
  end

  it "captures the controller action as a callee when requested" do
    source = <<-TS
      Route.get('/users', 'UsersController.index')
      TS

    routes = Noir::TreeSitterAdonisJsExtractor.extract_routes(source, include_callees: true)
    routes.first.callees.map(&.[0]).should contain("UsersController.index")
  end
end
