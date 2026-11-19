module API
  class Base < Grape::API
    format :json
    mount API::V1::Users
  end
end
