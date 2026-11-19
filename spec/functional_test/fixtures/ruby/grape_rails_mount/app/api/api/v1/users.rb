module API
  module V1
    class Users < Grape::API
      version 'v1', using: :path

      resource :users do
        get do
          User.all
        end
        get ':id' do
          User.find(params[:id])
        end
      end
    end
  end
end
