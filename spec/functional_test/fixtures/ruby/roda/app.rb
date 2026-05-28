require "roda"

class App < Roda
  route do |r|
    r.root do
      puts r.params["q"]
    end

    r.on "users" do
      r.get do
        puts r.params["page"]
      end

      r.post do
      end

      r.on :id do
        r.get do
          puts request.env["HTTP_X_TOKEN"]
        end

        r.put do
        end

        r.delete do
          puts r.cookies["session"]
        end
      end
    end

    r.on "api" do
      r.on "v1" do
        r.get "items" do
        end
      end
    end

    r.is "projects", Integer do |project_id|
      r.get do
      end
    end

    r.on "teams" do
      r.get Integer do |team_id|
      end
    end

    r.on "organizations" do
      r.on :org_id, Integer do |org_id, project_id|
        r.get do
        end
      end
    end

    # Rodauth auth examples for ruby_auth tagger testing
    r.rodauth

    r.get "dashboard" do
      rodauth.require_authentication
      "dashboard"
    end

    r.get "profile" do
      if rodauth.logged_in?
        "profile"
      else
        r.halt 401
      end
    end
  end
end
