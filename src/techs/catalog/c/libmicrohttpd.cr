# NoirTechs catalog entry: c_libmicrohttpd.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::C
  LIBMICROHTTPD = {
    :c_libmicrohttpd => {
      :framework => "libmicrohttpd",
      :language  => "C",
      :similar   => ["libmicrohttpd", "microhttpd", "mhd", "gnu-libmicrohttpd", "c-libmicrohttpd", "c_libmicrohttpd"],
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
      :context => {:callee => true},
    },
  }
end
