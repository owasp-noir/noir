# NoirTechs catalog entry: graphql_sdl.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  GRAPHQL_SDL = {
    # `:graphql` used to sit here with no analyzer and no detector behind it
    # — a catalog entry that advertised support nothing could deliver, and
    # whose `"graphql"` / `".graphql"` aliases resolved to that dead end
    # instead of to the analyzer that really reads those files. The aliases
    # moved onto `graphql_sdl`, whose detector already claims `.graphql`
    # (see `Detector::Specification::GraphqlSdl#applicable?`), so `-t
    # graphql` now selects a tech that produces endpoints.
    :graphql_sdl => {
      :format    => ["GRAPHQL_SDL"],
      :similar   => ["graphql_sdl", "graphql-sdl", "graphql_schema", ".graphqls", "graphql", ".graphql"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
