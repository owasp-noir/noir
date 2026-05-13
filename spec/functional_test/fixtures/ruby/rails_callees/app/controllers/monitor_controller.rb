class MonitorController < ApplicationController
  def status
    status = Health.check()
    render(json: status_payload(status))
  end
end
