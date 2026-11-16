class ReportsController < ApplicationController
  def index
    @reports = Report.where("title LIKE '%#{params[:q]}%'")
  end

  def ordered
    @reports = Report.all.order("created_at #{params[:dir]}")
  end

  def notify
    `logger -t report #{params[:id]}`
    head :ok
  end

  def convert
    output = %x(convert #{params[:src]} out.png)
    head :ok
  end

  def safe
    @reports = Report.where("title LIKE ?", "%#{params[:q]}%")
    flash[:notice] = "Run `rake reports:refresh #{params[:q]}` to rebuild"
  end
end
