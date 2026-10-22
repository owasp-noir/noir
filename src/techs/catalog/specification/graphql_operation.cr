# NoirTechs catalog entry: graphql_operation.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  GRAPHQL_OPERATION = {
    # The client half of the GraphQL surface: `query Foo { … }` /
    # `mutation Bar { … }` documents shipped as `.graphql` / `.gql` files,
    # as opposed to the `type Query { … }` SDL schema `graphql_sdl` reads.
    #
    # It had no catalog entry until now because the analyzer behind it was
    # a `FileAnalyzer` hook rather than a registered tech analyzer: its
    # endpoints came out with `"technology": null`, and because the hook ran
    # outside the tech registry, `--only-techs <anything>` returned them as
    # well. Naming the technology is what lets a report group them and
    # `--only-techs graphql_operation` / `--exclude-techs graphql_operation`
    # address them.
    #
    # `"graphql"` and `".graphql"` are deliberately NOT claimed here — they
    # are `graphql_sdl`'s aliases and moving them would silently repoint
    # every existing `-t graphql` at a different analyzer.
    :graphql_operation => {
      :format  => ["GRAPHQL"],
      :similar => ["graphql_operation", "graphql-operation", "graphql_operations",
                   "graphql-operations", "graphql_document", "graphql-document"],
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
