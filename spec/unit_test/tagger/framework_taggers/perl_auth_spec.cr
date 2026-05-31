require "../../../spec_helper"
require "../../../../src/tagger/tagger"

def perl_auth_tag_for(path, line, options)
  details = Details.new(PathInfo.new(path, line))
  details.technology = "perl_dancer2"
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
end
