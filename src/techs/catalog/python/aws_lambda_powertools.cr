# NoirTechs catalog entry: python_aws_lambda_powertools.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  AWS_LAMBDA_POWERTOOLS = {
    :python_aws_lambda_powertools => {
      :framework => "AWS Lambda Powertools",
      :language  => "Python",
      :similar   => ["aws-lambda-powertools", "aws_lambda_powertools", "python-aws-lambda-powertools", "python_aws_lambda_powertools"],
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
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
