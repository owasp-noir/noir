# NoirTechs catalog: aspnet technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  ASPNET = {
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
