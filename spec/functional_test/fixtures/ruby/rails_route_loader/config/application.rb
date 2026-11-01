require_relative 'boot'
require 'rails/all'

module Sample
  class Application < Rails::Application
    config.api_path = '/api/v1'
    config.unrelated = "x"
    config.base = '/base'
    config.devonly = '/devonly'
    config.cond = '/c'
  end
end
