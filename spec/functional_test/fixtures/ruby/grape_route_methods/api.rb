require "grape"

class CatalogAPI < Grape::API
  prefix :api

  get :status do
    { ok: true }
  end

  route %w[GET POST], "bulk" do
    status 202
  end

  params do
    requires :name, type: String
  end
  route ["PUT", "PATCH"], "items/:id" do
    Item.find(params[:id]).update!(name: params[:name], note: params[:note])
  end

  route :any, "*path" do
    error!("not found", 404)
  end
end
