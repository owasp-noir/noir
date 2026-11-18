class OrdersController < ApplicationController
  def create
    order = params.require(:order)
    Order.create(order.permit(:quantity, :note))
  end
end
