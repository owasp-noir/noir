# NoirTechs catalog entry: ios.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Mobile
  IOS = {
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
  }
end
