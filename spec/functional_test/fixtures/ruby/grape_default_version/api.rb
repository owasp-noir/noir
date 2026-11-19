module Twitter
  class API < Grape::API
    version 'v1'
    prefix :api

    resource :statuses do
      get :public_timeline do
        Status.limit(20)
      end
    end
  end
end
