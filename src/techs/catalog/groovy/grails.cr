# NoirTechs catalog entry: groovy_grails.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Groovy
  GRAILS = {
    :groovy_grails => {
      :framework => "Grails",
      :language  => "Groovy",
      :similar   => ["grails", "groovy_grails", "groovy-grails"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
