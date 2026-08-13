# NoirTechs catalog entry: cs_fastendpoints.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  FASTENDPOINTS = {
    :cs_fastendpoints => {
      :framework => "FastEndpoints",
      :language  => "C#",
      :similar   => ["fastendpoints", "fast-endpoints", "cs-fastendpoints", "cs_fastendpoints", "c# fastendpoints", "c#-fastendpoints", "c#_fastendpoints"],
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
