# NoirTechs catalog entry: payload_cms.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  PAYLOAD_CMS = {
    :payload_cms => {
      :format    => ["TS", "JS"],
      :similar   => ["payload", "payloadcms", "payload-cms", "payload_cms", "payload cms"],
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
