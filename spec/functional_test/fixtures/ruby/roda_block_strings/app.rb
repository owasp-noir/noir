require "roda"

class App < Roda
  route do |r|
    r.on "tasks" do
      r.get "next" do
        "There is nothing to do"
      end
      r.get "list" do
        "tasks"
      end
    end

    r.on "users" do
      r.get "me" do
        "me"
      end
    end

    r.get "health" do
      "ok"
    end
  end
end
