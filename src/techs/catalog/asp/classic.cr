# NoirTechs catalog entry: asp_classic.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Asp
  CLASSIC = {
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
