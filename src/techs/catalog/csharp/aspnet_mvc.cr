# NoirTechs catalog entry: cs_aspnet_mvc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  ASPNET_MVC = {
    :cs_aspnet_mvc => {
      :framework => "ASP.NET MVC",
      :language  => "C#",
      :similar   => ["asp.net mvc", "cs-aspnet-mvc", "cs_aspnet_mvc", "c# asp.net mvc", "c#-asp.net-mvc", "c#_aspnet_mvc"],
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
