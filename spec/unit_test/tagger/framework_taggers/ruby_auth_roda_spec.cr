require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# #3318: Rodauth guards follow the routing tree, not a fixed line window.
describe "RubyAuthTagger (Roda routing tree)" do
  roda_endpoint = ->(app : String, url : String, line : Int32) do
    details = Details.new(PathInfo.new(app, line))
    details.technology = "ruby_roda"
    Endpoint.new(url, "GET", [] of Param, details)
  end

  it "guards every route below require_authentication at the top of route do" do
    base = File.expand_path("../../../functional_test/fixtures/ruby/roda_tree", __DIR__)
    app = "#{base}/app.rb"
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    root = roda_endpoint.call(app, "/", 10)
    income = roda_endpoint.call(app, "/reports/income", 34)
    entry = roda_endpoint.call(app, "/reports/entry", 41)

    RubyAuthTagger.new(noir_options).perform([root, income, entry])

    [root, income, entry].each do |endpoint|
      endpoint.tags.map(&.description).should eq(["Protected by Rodauth require_authentication"])
    end
  end

  it "does not let a sibling branch's guard cover an earlier public route" do
    dir = File.tempname("noir_roda_leak")
    Dir.mkdir_p(dir)
    app = File.join(dir, "app.rb")
    File.write(app, <<-RB)
      class App < Roda
        plugin :rodauth
        route do |r|
          r.get 'public' do
            'anyone'
          end

          r.on 'admin' do
            rodauth.require_authentication
            r.get 'panel' do
              'secret'
            end
          end

          r.get 'after' do
            'anyone'
          end
        end
      end
      RB

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      public_route = roda_endpoint.call(app, "/public", 4)
      panel = roda_endpoint.call(app, "/admin/panel", 10)
      after = roda_endpoint.call(app, "/after", 15)

      RubyAuthTagger.new(noir_options).perform([public_route, panel, after])

      public_route.tags.should be_empty
      after.tags.should be_empty
      panel.tags.map(&.description).should eq(["Protected by Rodauth require_authentication"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
