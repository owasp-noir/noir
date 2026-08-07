# NoirTechs catalog: asp technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  ASP = {
    :asp_classic => {
      :framework => "Classic ASP (VBScript)",
      :language  => "ASP",
      :similar   => ["asp", "classic-asp", "classic_asp", "asp-classic", "asp_classic", "vbscript"],
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
