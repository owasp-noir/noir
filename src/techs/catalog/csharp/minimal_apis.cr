# NoirTechs catalog entry: cs_aspnet_core_minimal_api.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  MINIMAL_APIS = {
    :cs_aspnet_core_minimal_api => {
      :framework => "ASP.NET Core Minimal API",
      :language  => "C#",
      :similar   => ["asp.net core minimal api", "asp.net core minimal apis", "minimal api", "minimal apis", "cs-aspnet-core-minimal-api", "cs_aspnet_core_minimal_api", "c# asp.net core minimal api", "c#-aspnet-core-minimal-api", "c#_aspnet_core_minimal_api"],
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
