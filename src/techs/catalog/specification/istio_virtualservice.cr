# NoirTechs catalog entry: istio_virtualservice.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  ISTIO_VIRTUALSERVICE = {
    :istio_virtualservice => {
      :format    => ["YAML"],
      :similar   => ["istio", "virtualservice", "networking.istio.io"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
