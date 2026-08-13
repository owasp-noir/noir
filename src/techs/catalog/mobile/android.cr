# NoirTechs catalog entry: android.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Mobile
  ANDROID = {
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
  }
end
