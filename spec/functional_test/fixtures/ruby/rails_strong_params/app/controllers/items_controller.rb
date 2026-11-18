class ItemsController < ApplicationController
  def create
    Item.create(item_params)
  end

  def update
    Item.find(params[:id]).update(item_params)
  end

  private

  def item_params
    params_for(:item).permit(:name, :price)
  end
end
