# NoirTechs catalog entry: cpp_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cpp
  CLI = {
    :cpp_cli => {
      :framework => "CLI (CLI11 / getopt / cxxopts / boost.program_options / gflags / Abseil Flags / argparse)",
      :language  => "C++",
      :similar   => ["cpp-cli", "cpp_cli", "cli11", "getopt", "cxxopts", "program_options", "gflags", "abseil", "absl-flags", "argparse"],
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
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
