require "../../spec_helper"
require "../../../src/miniparsers/egg_router_extractor"

describe Noir::EggRouterExtractor do
  it "reads verbs, named routes, resources, redirects and namespaces" do
    content = <<-JS
      module.exports = app => {
        const { router, controller } = app;
        router.get('/a', controller.a.index);
        router.post('named', '/b', auth, 'b.create');
        app.router.resources('/c/', controller.c);
        router.redirect('/d', '/e', 302);
        const v1 = router.namespace('/v1');
        v1.del('/f/:id', controller.f.destroy,);
        app.get('/g', controller.g.show);
      };
      JS
    routes = Noir::EggRouterExtractor.extract(content)
    routes.map { |r| {r.verb, r.path, r.handler, r.line} }.should eq [
      {"get", "/a", "controller.a.index", 3},
      {"post", "/b", "'b.create'", 4},
      {"resources", "/c/", "controller.c", 5},
      {"redirect", "/d", "302", 6},
      {"del", "/v1/f/:id", "controller.f.destroy", 8},
      {"get", "/g", "controller.g.show", 9},
    ]
  end

  it "keeps a two-argument string handler as the controller, not the path" do
    routes = Noir::EggRouterExtractor.extract(%(router.get('/home', 'home.index');))
    routes.map { |r| {r.path, r.handler} }.should eq [{"/home", "'home.index'"}]
  end

  it "skips comments, other receivers and non-path calls" do
    content = <<-JS
      // router.get('/commented', controller.x.y);
      this.app.get('/nested', controller.x.y);
      client.get('/foreign', handler);
      router.get(`/${dynamic}`, controller.x.y);
      app.get('env');
      JS
    Noir::EggRouterExtractor.extract(content).should be_empty
  end
end
