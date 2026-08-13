# NoirTechs catalog entry: dart_shelf.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Dart
  SHELF = {
    :dart_shelf => {
      :framework => "Shelf",
      :language  => "Dart",
      :similar   => ["shelf", "dart_shelf", "dart-shelf", "shelf_router", "shelf-router"],
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
