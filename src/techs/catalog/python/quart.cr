# NoirTechs catalog entry: python_quart.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  QUART = {
    :python_quart => {
      :framework => "Quart",
      :language  => "Python",
      :similar   => ["quart", "python-quart", "python_quart"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => true,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
