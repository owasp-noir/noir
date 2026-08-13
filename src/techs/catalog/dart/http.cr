# NoirTechs catalog entry: dart_http.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  HTTP = {
    :dart_http => {
      :framework => "dart:io HttpServer",
      :language  => "Dart",
      :similar   => ["dart_http", "dart-http", "dart:io", "dart io", "dart_httpserver", "httpserver"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
