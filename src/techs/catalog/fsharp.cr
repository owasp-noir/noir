# NoirTechs catalog: fsharp technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  FSHARP = {
    :fs_giraffe => {
      :framework => "Giraffe",
      :language  => "F#",
      :similar   => ["giraffe", "fs-giraffe", "fs_giraffe", "fsharp-giraffe", "fsharp_giraffe", "f#-giraffe", "f#_giraffe"],
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
