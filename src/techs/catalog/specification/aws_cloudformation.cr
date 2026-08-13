# NoirTechs catalog entry: aws_cloudformation.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  AWS_CLOUDFORMATION = {
    :aws_cloudformation => {
      :format    => ["YAML", "JSON"],
      :similar   => ["aws cloudformation", "aws sam", "cloudformation", "sam", "template.yaml", "template.yml", "aws::serverless::function", "aws::apigateway::resource"],
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
