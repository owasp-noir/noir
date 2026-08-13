# NoirTechs catalog entry: well_known_applinks.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Mobile
  WELL_KNOWN = {
    :well_known_applinks => {
      :format    => ["JSON"],
      :similar   => ["well_known_applinks", "assetlinks", "apple-app-site-association", "aasa", "applinks"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
