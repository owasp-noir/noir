# NoirTechs catalog entry: vb_aspnet_mvc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Vb
  ASPNET_MVC = {
    :vb_aspnet_mvc => {
      :framework => "ASP.NET MVC / Web API",
      :language  => "VB.NET",
      :similar   => ["vb-aspnet-mvc", "vb_aspnet_mvc", "vb.net asp.net mvc", "vb.net web api", "vbnet-aspnet-mvc", "vbnet_aspnet_mvc"],
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
    },
  }
end
