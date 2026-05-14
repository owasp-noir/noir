require "../../spec_helper"
require "../../../src/miniparsers/elixir_callee_extractor"

describe Noir::ElixirCalleeExtractor do
  it "extracts qualified and local calls from Elixir handler bodies with line numbers" do
    body = <<-ELIXIR
      users = UserService.list(conn.query_params["page"])
      AuditLog.write("list")
      send_resp(conn, 200, JsonPresenter.render(users))
      ELIXIR

    callees = Noir::ElixirCalleeExtractor.callees_for_body(body, "router.ex", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService.list", 10},
      {"AuditLog.write", 11},
      {"JsonPresenter.render", 12},
      {"send_resp", 12},
    ])
  end

  it "skips comments, strings, and language keywords while keeping pipe calls" do
    body = <<-ELIXIR
      # AuditLog.write("ignored")
      message = "DangerService.run()"
      created = payload |> UserService.create()
      Notifier.deliver created
      send_resp conn, 201, render_user(created)
      if Health.ready?() do
        send_resp(conn, 200, "ok")
      end
      ELIXIR

    callees = Noir::ElixirCalleeExtractor.callees_for_body(body, "router.ex", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService.create", 22},
      {"Notifier.deliver", 23},
      {"send_resp", 24},
      {"render_user", 24},
      {"Health.ready?", 25},
      {"send_resp", 26},
    ])
  end
end
