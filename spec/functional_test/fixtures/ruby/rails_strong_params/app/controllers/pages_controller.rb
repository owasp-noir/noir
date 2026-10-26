class PagesController < ApplicationController
  def update
    Page.find(params[:id]).update(slug: params.dig(:page, :slug_suffix))
  end
end
