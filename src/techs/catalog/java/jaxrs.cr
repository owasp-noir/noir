# NoirTechs catalog entry: java_jaxrs.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  JAXRS = {
    :java_jaxrs => {
      :framework => "JAX-RS",
      :language  => "Java",
      :similar   => ["jaxrs", "jax-rs", "jakarta-rest", "java-jaxrs", "java_jaxrs"],
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
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
