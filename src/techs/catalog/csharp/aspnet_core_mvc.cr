# NoirTechs catalog entry: cs_aspnet_core_mvc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  ASPNET_CORE_MVC = {
    :cs_aspnet_core_mvc => {
      :framework => "ASP.NET Core MVC",
      :language  => "C#",
      :similar   => ["asp.net core mvc", "asp.net core", "aspnetcore", "cs-aspnet-core-mvc", "cs_aspnet_core_mvc", "c# asp.net core mvc", "c#-asp.net-core-mvc", "c#_aspnet_core_mvc"],
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
