require "roda"

class App < Roda
  route do |r|
    r.root do
      HomeService.index
      json serialize_home()
    end

    r.on "users" do
      r.get do
        page = r.params["page"]
        users = UserService.list(page)
        response.write serialize_users(users)
      end

      r.post do; UserService.create(JSON.parse(r.body.read)); end

      r.on :id do
        r.get do
          user = if Feature.enabled?
            UserService.find(id)
          else
            UserFallback.find(id)
          end
          response.write serialize_user(user)
        end

        r.delete do
          UserService.delete(id)
          response.status = 204
        end

        r.patch "toggle" do
          state = if Feature.enabled? then UserService.enable(id) else UserService.disable(id) end
          response.write serialize_state(state)
        end

        r.options { OptionsService.allow(id) }
      end
    end
  end
end
