# NoirTechs catalog entry: apex_salesforce.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Apex
  SALESFORCE = {
    :apex_salesforce => {
      :framework => "Salesforce (REST, Aura, SOAP)",
      :language  => "Apex",
      :similar   => ["apex", "salesforce", "sfdx", "apex-rest", "apex_rest", "apex_salesforce"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
