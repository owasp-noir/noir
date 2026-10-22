# NoirTechs catalog entry: dart_angel3.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  ANGEL3 = {
    :dart_angel3 => {
      :framework => "Angel3",
      :language  => "Dart",
      :similar   => ["angel", "angel3", "dart_angel3", "dart-angel3", "angel_framework", "angel3_framework"],
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
