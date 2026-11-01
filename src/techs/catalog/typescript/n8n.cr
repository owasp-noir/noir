# NoirTechs catalog entry: ts_n8n.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  N8N = {
    :ts_n8n => {
      :framework => "n8n",
      :language  => "TypeScript",
      :similar   => ["n8n", "ts-n8n", "ts_n8n", "n8n-decorators"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
