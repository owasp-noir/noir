# NoirTechs catalog entry: python_robyn.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  ROBYN = {
    :python_robyn => {
      :framework => "Robyn",
      :language  => "Python",
      :similar   => ["robyn", "python-robyn", "python_robyn"],
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
        :websocket   => true,
      },
      :context => {:callee => true},
    },
  }
end
