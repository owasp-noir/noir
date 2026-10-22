# NoirTechs catalog entry: krakend.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  KRAKEND = {
    :krakend => {
      :format    => ["JSON"],
      :similar   => ["krakend", "krakend.json", "krakend api gateway"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => false,
          :header => true,
          :cookie => false,
        },
      },
    },
  }
end
