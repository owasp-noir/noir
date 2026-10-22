# NoirTechs catalog entry: burp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  BURP = {
    :burp => {
      :format    => ["XML"],
      :similar   => ["burp", "burpsuite", "burp-suite", "burp_suite", "burp-sitemap"],
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
      },
    },
  }
end
