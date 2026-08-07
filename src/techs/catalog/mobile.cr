# NoirTechs catalog: mobile app entry-point sources.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  MOBILE = {
    :android => {
      :format    => ["XML"],
      :similar   => ["android", "android-manifest", "androidmanifest", "android_manifest"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
      :context => {:callee => true, :guards => true},
    },
    :ios => {
      :format    => ["PLIST"],
      :similar   => ["ios", "info-plist", "infoplist", "info_plist", "entitlements"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
      :context => {:callee => true, :guards => true},
    },
    :well_known_applinks => {
      :format    => ["JSON"],
      :similar   => ["well_known_applinks", "assetlinks", "apple-app-site-association", "aasa", "applinks"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
