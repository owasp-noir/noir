require "grape"

class API < Grape::API
  prefix "api"

  resource :users do
    params do
      optional :page, type: Integer
    end

    get do # comment mentions end
      users = UserService.list(params[:page])
      AuditLog.write("list")
      present serialize_users(users)
    end

    params do
      requires :name, type: String
    end

    post do
      payload = BuildUser.call(params[:name])
      created = UserService.create(payload)
      present serialize_user(created)
    end

    get ":id" do
      status = if Feature.enabled?
        UserService.find(params[:id])
      else
        UserFallback.find(params[:id])
      end
      present serialize_user(status)
    end

    delete ":id" do; UserService.delete(params[:id]); end
  end
end
