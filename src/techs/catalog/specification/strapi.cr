# NoirTechs catalog entry: strapi.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  STRAPI = {
    :strapi => {
      :format    => ["JSON", "TS", "JS"],
      :similar   => ["strapi", "strapi5", "strapi-cms", "strapi_cms", "strapi v4", "strapi v5"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
