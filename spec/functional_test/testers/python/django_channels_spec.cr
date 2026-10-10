require "../../func_spec.cr"

# Django Channels: lists passed to `URLRouter(...)` are WebSocket routes
# (protocol "ws"), including `a + [...]` concatenation, nested
# `path(prefix, URLRouter(...))` mounts and an unmounted
# `websocket_urlpatterns`. `chat/routing.py`'s `unused_patterns` is never
# handed to a URLRouter, so `/not-mounted/` must not appear, and the nested
# inline `URLRouter([...])` body must not leak out as a bare `/chat/`.
# A commented-out or docstring `URLRouter` in `asgi.py` is not a router, and
# `path(prefix, AuthMiddlewareStack(URLRouter(...)))` is nested, not a root.
ws = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "GET", params)
  ep.protocol = "ws"
  ep
end

expected_endpoints = [
  Endpoint.new("/index/", "GET"),
  ws.call("/ws/chat/<str:room_name>/", [Param.new("room_name", "", "path")]),
  ws.call("/game/play/<int:match_id>/", [Param.new("match_id", "", "path")]),
  ws.call("/game/lobby/chat/", [] of Param),
  ws.call("/live/{feed}/", [Param.new("feed", "", "path")]),
  ws.call("/ws/notes/", [] of Param),
  ws.call("/ws/secure/lobby/", [] of Param),
]

tester = FunctionalTester.new("fixtures/python/django_channels/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Django Channels route lines", tags: "functional" do
  it "points each WebSocket route at its path() line" do
    lines = tester.endpoints.select(&.protocol.==("ws")).to_h do |ep|
      info = ep.details.code_paths.first
      {ep.url, "#{File.basename(info.path)}:#{info.line}"}
    end
    lines["/ws/chat/<str:room_name>/"].should eq("routing.py:12")
    lines["/game/lobby/chat/"].should eq("routing.py:9")
    lines["/live/{feed}/"].should eq("asgi.py:31")
  end
end
