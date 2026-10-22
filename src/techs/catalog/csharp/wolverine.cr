# NoirTechs catalog entry: cs_wolverine.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  WOLVERINE = {
    :cs_wolverine => {
      :framework => "Wolverine.Http",
      :language  => "C#",
      :similar   => ["wolverine", "wolverinefx", "wolverine-http", "wolverine_http", "cs-wolverine", "cs_wolverine", "c# wolverine", "c#-wolverine", "c#_wolverine"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
