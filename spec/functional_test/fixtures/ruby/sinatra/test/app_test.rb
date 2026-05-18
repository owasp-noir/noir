# Regression guard: Minitest's `*_test.rb` convention skips file
# scanning. Routes registered in this file (the inline TestApp
# Sinatra::Base subclass below) should NOT surface as endpoints.
require 'sinatra/base'
require 'minitest/autorun'

class TestApp < Sinatra::Base
  get '/should-not-appear-test-get' do
    'ok'
  end

  post '/should-not-appear-test-post' do
    'ok'
  end
end

class AppTest < Minitest::Test
  def test_noop
    assert true
  end
end
