# NoirTechs catalog entry: js_socketio.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  SOCKETIO = {
    :js_socketio => {
      :framework => "Socket.IO",
      :language  => "JavaScript",
      :similar   => ["socket.io", "socketio", "socket-io", "js-socketio", "js_socketio"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
  }
end
