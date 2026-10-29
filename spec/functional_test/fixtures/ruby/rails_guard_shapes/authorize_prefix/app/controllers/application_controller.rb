class ApplicationController < ActionController::Base
  before_action :authorize_mini_profiler

  def authorize_mini_profiler
    Rack::MiniProfiler.authorize_request if mini_profiler_enabled?
  end

  def mini_profiler_enabled?
    return true if Rails.env.development?
    current_user&.developer?
  end

  def current_user
    return nil if request.headers["Api-Key"].blank?
    raise Discourse::InvalidAccess unless ApiKey.active.exists?(key: request.headers["Api-Key"])
    ApiKey.find_by(key: request.headers["Api-Key"]).user
  end
end
