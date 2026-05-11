class Rails::HealthController < ApplicationController
  def show
    request.headers['X-Health']
  end
end
