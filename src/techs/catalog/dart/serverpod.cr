# NoirTechs catalog entry: dart_serverpod.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  SERVERPOD = {
    :dart_serverpod => {
      :framework => "Serverpod",
      :language  => "Dart",
      :similar   => ["serverpod", "dart_serverpod", "dart-serverpod"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
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
