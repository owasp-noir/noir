# NoirTechs catalog entry: dart_get_server.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  GET_SERVER = {
    :dart_get_server => {
      :framework => "GetServer",
      :language  => "Dart",
      :similar   => ["get_server", "getserver", "dart_get_server", "dart-get-server"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
