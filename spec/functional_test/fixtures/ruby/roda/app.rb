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
  end
end
