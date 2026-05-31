require "../../../spec_helper"
require "../../../../src/tagger/tagger"

def perl_auth_tag_for(path, line, options, tech = "perl_dancer2")
  details = Details.new(PathInfo.new(path, line))
  details.technology = tech
  endpoint = Endpoint.new("/x", "GET", [] of Param, details)
  PerlAuthTagger.new(options).perform([endpoint])
  endpoint
end

describe "PerlAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/perl/dancer2_auth"
  app_path = "#{fixture_base}/lib/MyApp.pm"
  guarded_path = "#{fixture_base}/lib/Guarded.pm"

  # lib/MyApp.pm line reference:
  #  5: get '/admin'    => require_role Admin => sub {
  #  9: get '/me'       => require_login sub {
  # 13: post '/reports' => require_any_role ['Admin', 'Auditor'] => sub {
  # 17: get '/dashboard' => sub {           # body calls logged_in_user
  # 23: get '/public'   => sub {            # no guard

  it "detects the Dancer2 require_role wrapper" do
    endpoint = perl_auth_tag_for(app_path, 5, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("perl_auth")
    endpoint.tags[0].description.should contain("require_role")
  end

  it "detects the Dancer2 require_login wrapper" do
    endpoint = perl_auth_tag_for(app_path, 9, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("require_login")
  end

  it "detects the Dancer2 require_any_role wrapper" do
    endpoint = perl_auth_tag_for(app_path, 13, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("require_any_role")
  end

  it "detects logged_in_user inside the handler body" do
    endpoint = perl_auth_tag_for(app_path, 17, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("logged_in_user")
  end

  it "leaves unguarded routes untagged" do
    endpoint = perl_auth_tag_for(app_path, 23, create_test_options)
    endpoint.tags.empty?.should be_true
  end

  it "detects an application-wide `hook before` guard" do
    endpoint = perl_auth_tag_for(guarded_path, 10, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("hook before")
  end

  # 29: get '/subscription' =>
  # 30:     require_login sub {
  it "follows a multi-line wrapper past a path containing `sub`" do
    endpoint = perl_auth_tag_for(app_path, 29, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("require_login")
  end

  it "labels a Catalyst `sub auto` global guard as Catalyst, not Dancer2" do
    catalyst_path = "#{__DIR__}/../../../functional_test/fixtures/perl/catalyst_auth/lib/Admin.pm"
    endpoint = perl_auth_tag_for(catalyst_path, 13, create_test_options, "perl_catalyst")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("Catalyst")
    endpoint.tags[0].description.should_not contain("Dancer2")
  end
end
