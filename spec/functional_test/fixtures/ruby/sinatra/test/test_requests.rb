# Regression guard: Test::Unit / Minitest also use the `test_*.rb`
# PREFIX convention (gollum's `test/test_app.rb` is the canonical
# example). The inline Rack::Test request calls below look exactly
# like Sinatra route registrations to the line matcher and must NOT
# surface as endpoints.
require 'test/unit'
require 'rack/test'

class RequestsTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def test_pages
    get '/should-not-appear-prefix-get'
    post '/should-not-appear-prefix-post'
    assert last_response.ok?
  end
end
