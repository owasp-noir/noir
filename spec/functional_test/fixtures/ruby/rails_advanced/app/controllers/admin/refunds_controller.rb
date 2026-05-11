class Admin::RefundsController < ApplicationController
  def change_status
    request.headers['X-Refund-Reason']
    params[:status]
  end

  def new_list
    request.headers['X-Page']
  end
end
