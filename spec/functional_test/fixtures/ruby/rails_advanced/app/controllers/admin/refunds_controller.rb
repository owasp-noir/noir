class Admin::RefundsController < ApplicationController
  def change_status
    request.headers['X-Refund-Reason']
    params[:status]
  end

  def new_list
    request.headers['X-Page']
  end

  def purge
    request.headers['X-Confirm']
    params["id"]
  end

  def update_metadata
    params.require(:refund).permit("note", "kind")
  end
end
