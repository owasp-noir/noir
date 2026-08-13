# NoirTechs catalog entry: aws_cdk.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  AWS_CDK = {
    :aws_cdk => {
      :format    => ["TS", "JS", "PY"],
      :similar   => ["aws cdk", "aws-cdk-lib", "@aws-cdk", "cdk", "aws_cdk"],
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
