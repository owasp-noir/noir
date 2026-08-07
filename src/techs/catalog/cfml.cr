# NoirTechs catalog: cfml technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  CFML = {
    :cfml_taffy => {
      :framework => "Taffy",
      :language  => "CFML",
      :similar   => ["taffy", "cfml-taffy", "cfml_taffy", "coldfusion-taffy"],
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
    },
    :cfml_coldbox => {
      :framework => "ColdBox",
      :language  => "CFML",
      :similar   => ["coldbox", "cfml-coldbox", "cfml_coldbox", "contentbox"],
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
    },
    :cfml_wheels => {
      :framework => "Wheels",
      :language  => "CFML",
      :similar   => ["wheels", "cfwheels", "cfml-wheels", "cfml_wheels"],
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
    },
    :cfml_fw1 => {
      :framework => "FW/1",
      :language  => "CFML",
      :similar   => ["fw1", "fw/1", "framework-one", "framework.one", "cfml-fw1", "cfml_fw1"],
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
    },
    :cfml_pure => {
      :framework => "ColdFusion (CFML)",
      :language  => "CFML",
      :similar   => ["cfml", "coldfusion", "cfml-pure", "cfml_pure", "lucee", "boxlang"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
