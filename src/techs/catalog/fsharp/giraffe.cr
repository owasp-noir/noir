# NoirTechs catalog entry: fs_giraffe.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Fsharp
  GIRAFFE = {
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
