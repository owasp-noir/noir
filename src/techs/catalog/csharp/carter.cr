# NoirTechs catalog entry: cs_carter.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  CARTER = {
    :cs_carter => {
      :framework => "Carter",
      :language  => "C#",
      :similar   => ["carter", "cs-carter", "cs_carter", "c# carter", "c#-carter", "c#_carter"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
