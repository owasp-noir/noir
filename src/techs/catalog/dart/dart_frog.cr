# NoirTechs catalog entry: dart_frog.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  DART_FROG = {
    :dart_frog => {
      :framework => "Dart Frog",
      :language  => "Dart",
      :similar   => ["dart_frog", "dart-frog", "dartfrog", "dart frog"],
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
        :websocket   => true,
      },
      :context => {:callee => true},
    },
  }
end
