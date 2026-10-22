# NoirTechs catalog entry: aspnet_webforms.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Aspnet
  WEBFORMS = {
    :aspnet_webforms => {
      :framework => "ASP.NET WebForms",
      :language  => "ASP.NET",
      :similar   => ["webforms", "web-forms", "aspnet-webforms", "aspnet_webforms", "asp.net webforms", "aspx"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
