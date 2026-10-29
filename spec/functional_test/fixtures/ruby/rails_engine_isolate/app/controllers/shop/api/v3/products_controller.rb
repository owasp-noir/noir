module Shop
  module Api
    module V3
      class ProductsController < ActionController::API
        def index
          render json: Product.where(q: params[:q])
        end

        def show
          render json: Product.find(params[:id])
        end
      end
    end
  end
end
