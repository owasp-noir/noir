# NoirTechs catalog entry: dart_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  CLI = {
    :dart_cli => {
      :framework => "CLI (args / CommandRunner / dcli)",
      :language  => "Dart",
      :similar   => ["dart-cli", "dart_cli", "args", "dcli", "commandrunner"],
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
        :websocket   => false,
      },
    },
  }
end
