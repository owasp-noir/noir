require "../../spec_helper"
require "../../../src/miniparsers/js_registrar_defaults"

describe Noir::JSRegistrarDefaults do
  it "follows the same map and key through a local registrar" do
    source = <<-JS
      const features = { news: require('./news') };
      function place(paths, other) {
        Object.keys(paths).map(key => {
          const original = key;
          key = paths[original];
          features[original](router, key, other[original]);
        });
      }
      function configure(paths) {
        const keys = ['news', 'books'];
        keys.forEach(key => { if (!(key in paths)) paths[key] = key; });
        place(paths, {});
      }
      JS
    Noir::JSRegistrarDefaults.extract(source, "index.js").should eq([
      Noir::JSRegistrarDefaults::Argument.new("features.news", "./news", 1, "news"),
      Noir::JSRegistrarDefaults::Argument.new("features.books", nil, 1, "books"),
    ])
  end

  it "leaves a runtime list shadowing the outer constant unresolved" do
    source = <<-JS
      const keys = ['unrelated'];
      function configure(keys, paths) {
        keys.forEach(k => { paths[k] = k; });
        Object.keys(paths).forEach(k => { routes[k](router, paths[k]); });
      }
      JS
    Noir::JSRegistrarDefaults.extract(source, "index.js").should be_empty
  end
end
