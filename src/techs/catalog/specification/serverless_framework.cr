# NoirTechs catalog entry: serverless_framework.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  SERVERLESS_FRAMEWORK = {
    :serverless_framework => {
      :format    => ["YAML", "JSON"],
      :similar   => ["serverless framework", "serverless.yml", "serverless.yaml", "serverless.json", "aws lambda"],
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
