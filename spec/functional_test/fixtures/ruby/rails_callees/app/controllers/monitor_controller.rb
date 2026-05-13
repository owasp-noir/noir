class MonitorController < ApplicationController
  def status
    status = Health.check()
    render json: status_payload(status)
  end

  def ping; render plain: Health.check; end

  def ready
    render plain: Ready.check
  end
end
