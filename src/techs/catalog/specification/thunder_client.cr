# NoirTechs catalog entry: thunder_client.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  THUNDER_CLIENT = {
    :thunder_client => {
      :format    => ["JSON"],
      :similar   => ["thunder_client", "thunder-client", "thunderclient", "thunder-tests"],
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
      },
    },
  }
end
