require "../../spec_helper"
require "../../../src/analyzer/analyzers/ruby/sinatra.cr"

describe "mapping_to_path" do
  options = create_test_options
  instance = Analyzer::Ruby::Sinatra.new(options)

  it "line_to_param - param[]" do
    line = "param['id']"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - params[]" do
    line = "params['id']"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - headers[]" do
    line = "headers['x-token']"
    instance.line_to_param(line).name.should eq("x-token")
  end

  it "line_to_param - request.env" do
    line = "request.env[\"x-token\"]"
    instance.line_to_param(line).name.should eq("x-token")
  end

  # `line_to_endpoint` used to match verbs anywhere on the line
  # via a negative-lookbehind regex, so a Ruby string literal that
  # contained `get '/path'` text inside it (a docstring, a help
  # message, a test fixture comment, …) would surface as a real
  # route. Anchor to the start of the (stripped) line so only DSL
  # calls at statement boundary match.
  it "line_to_endpoint does not match a verb inside a string literal" do
    line = %q(hint = "Try get '/from-string' do ... end")
    instance.line_to_endpoint(line).method.should eq("")
  end

  it "line_to_endpoint still matches a real DSL call" do
    instance.line_to_endpoint(%q(get '/simple' do)).method.should eq("GET")
    instance.line_to_endpoint(%q(  post '/items' do)).method.should eq("POST")
    instance.line_to_endpoint(%q(get '/simple' do)).url.should eq("/simple")
  end

  # `"#{PREFIX}/items"` interpolations used to leak the raw
  # `#{PREFIX}` characters into the URL. Rewrite them as
  # `{PREFIX}` placeholders so the path-parameter extractor picks
  # them up and the URL template stays valid. The Sinatra
  # `sinatra_prefixed_path` step prepends the leading `/` —
  # `line_to_endpoint` itself returns the raw captured path.
  it "line_to_endpoint normalizes Ruby interpolation into {placeholder}" do
    line = %q(get "#{PREFIX}/items" do)
    instance.line_to_endpoint(line).url.should eq("{PREFIX}/items")
  end
end
