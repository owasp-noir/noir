class Admin::RefundsController < ApplicationController
  def change_status
    request.headers['X-Refund-Reason']
    params[:status]
  end

  def new_list
    request.headers['X-Page']
  end

  def summary
    request.headers['X-Summary']
  end

  def preview
    request.headers['X-Preview']
  end

  def template
    request.headers['X-Template']
  end

  def inline_summary
    request.headers['X-Inline-Summary']
  end

  def inline_preview
    request.headers['X-Inline-Preview']
  end

  def purge
    request.headers['X-Confirm']
    params["id"]
  end

  def update_metadata
    params.require(:refund).permit("note", "kind")
  end
end
