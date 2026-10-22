# NoirTechs catalog entry: terraform.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  TERRAFORM = {
    :terraform => {
      :format    => ["TF", "JSON"],
      :similar   => ["terraform", "tf", "hcl", "opentofu", "tofu", "aws_api_gateway", "aws_apigatewayv2", "aws_apigatewayv2_route"],
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
