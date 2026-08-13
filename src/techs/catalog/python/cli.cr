# NoirTechs catalog entry: python_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  CLI = {
    :python_cli => {
      :framework => "CLI (argparse / click / typer / fire / docopt / getopt / absl / cleo)",
      :language  => "Python",
      :similar   => ["python-cli", "python_cli", "argparse", "click", "typer", "fire", "docopt", "absl", "abseil", "cleo"],
      :supported => {
        :endpoint => true,
        # CLI endpoints carry the synthetic "CLI" verb, not an HTTP method,
        # and their inputs are flag/argument/env params, outside the HTTP
        # query/path/body/header/cookie buckets the docs table tracks.
        :method => false,
        :params => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
