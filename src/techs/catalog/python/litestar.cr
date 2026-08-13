# NoirTechs catalog entry: python_litestar.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  LITESTAR = {
    :python_litestar => {
      :framework => "Litestar",
      :language  => "Python",
      :similar   => ["litestar", "starlite", "python-litestar", "python_litestar"],
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
      :context => {:callee => true},
    },
  }
end
