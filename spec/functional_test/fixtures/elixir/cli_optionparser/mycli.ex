defmodule MyCli do
  def main(argv) do
    {opts, _args, _} =
      OptionParser.parse(argv,
        switches: [port: :integer, verbose: :boolean],
        aliases: [p: :port]
      )

    token = System.get_env("API_TOKEN")
    {opts, token}
  end
end
