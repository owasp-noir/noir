class MonitorController < ApplicationController
  def ping
    request.headers['X-Ping']
  end
end
