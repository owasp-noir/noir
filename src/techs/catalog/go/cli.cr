# NoirTechs catalog entry: go_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  CLI = {
    :go_cli => {
      :framework => "CLI (flag / cobra / urfave / pflag / go-arg / go-flags / kong / kingpin / mitchellh)",
      :language  => "Go",
      :similar   => ["go-cli", "go_cli", "cobra", "urfave", "go-arg", "go-flags", "pflag", "kong", "kingpin", "mitchellh-cli"],
      :supported => {
        :endpoint => true,
        # CLI endpoints carry the synthetic "CLI" verb, not an HTTP method,
        # and their inputs are flag/argument/env params, which are outside
        # the HTTP query/path/body/header/cookie buckets the docs table
        # tracks.
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
