require "../../../spec_helper"
require "../../../../src/detector/detectors/elixir/*"

describe "Detect Elixir Phoenix Channel" do
  options = create_test_options
  instance = Detector::Elixir::PhoenixChannel.new options

  it "detects a channel module using Phoenix.Channel directly" do
    channel = <<-EX
      defmodule MyAppWeb.RoomChannel do
        use Phoenix.Channel
        def handle_in("ping", _p, socket), do: {:reply, :pong, socket}
      end
      EX
    instance.detect("lib/my_app_web/channels/room_channel.ex", channel).should be_true
  end

  it "detects a channel module using the generated :channel clause" do
    channel = <<-EX
      defmodule MyAppWeb.NoticeChannel do
        use MyAppWeb, :channel
      end
      EX
    instance.detect("lib/my_app_web/channels/notice_channel.ex", channel).should be_true
  end

  it "detects a socket module's channel declaration" do
    socket = <<-EX
      defmodule MyAppWeb.UserSocket do
        use Phoenix.Socket
        channel "room:*", MyAppWeb.RoomChannel
      end
      EX
    instance.detect("lib/my_app_web/channels/user_socket.ex", socket).should be_true
  end

  it "ignores a plain Phoenix controller" do
    controller = <<-EX
      defmodule MyAppWeb.PageController do
        use MyAppWeb, :controller
        def index(conn, _params), do: render(conn, "index.html")
      end
      EX
    instance.detect("lib/my_app_web/controllers/page_controller.ex", controller).should be_false
  end
end
