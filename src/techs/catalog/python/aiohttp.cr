# NoirTechs catalog entry: python_aiohttp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  AIOHTTP = {
    :python_aiohttp => {
      :framework => "aiohttp",
      :language  => "Python",
      :similar   => ["aiohttp", "python-aiohttp", "python_aiohttp"],
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
