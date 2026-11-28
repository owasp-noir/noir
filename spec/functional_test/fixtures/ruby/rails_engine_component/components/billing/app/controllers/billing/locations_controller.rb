module Billing
  class LocationsController < ApplicationController
    def index; end

    def show; end

    def new; end

    def create
      params.require(:location).permit(:name)
    end

    def edit; end

    def update; end

    def destroy; end
  end
end
