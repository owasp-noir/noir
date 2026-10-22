# NoirTechs catalog entry: kamal.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  KAMAL = {
    :kamal => {
      :format    => ["YAML"],
      :similar   => ["kamal", "kamal deploy", "kamal-deploy", "kamal proxy", "deploy.yml"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
