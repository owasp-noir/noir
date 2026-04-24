require "grape"

class API < Grape::API
  version "v1", using: :header, vendor: "twitter"
  format :json

  resource :users do
    desc "Return list of users"
    get do
      User.all
    end

    desc "Return a user"
    params do
      requires :id, type: Integer
    end
    get ":id" do
      User.find(params[:id])
    end

    post do
      User.create!(params[:name])
    end

    put ":id" do
      User.find(params[:id]).update!(params)
    end

    delete ":id" do
      User.find(params[:id]).destroy
    end
  end

  namespace :orders do
    get do
    end

    post do
    end
  end
end
