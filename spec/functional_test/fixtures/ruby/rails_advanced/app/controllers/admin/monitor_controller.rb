class Admin::MonitorController < ApplicationController
  def heartbeat
    request.headers['X-Heartbeat']
    params["id"]
  end
end
