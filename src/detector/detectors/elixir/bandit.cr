require "../../../models/detector"

module Detector::Elixir
  class Bandit < Detector
    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      if basename == "mix.exs"
        return file_contents.includes?("{:bandit,") ||
          file_contents.includes?("{ :bandit,") ||
          file_contents.includes?("{:bandit_phoenix,") ||
          file_contents.includes?("Bandit.PhoenixAdapter")
      end

      # Phoenix endpoint config or application supervision tree often
      # names Bandit explicitly when it is the chosen HTTP server, e.g.
      # `adapter: Bandit.PhoenixAdapter` in `config/*.exs` or
      # `{Bandit, plug: MyApp.Router}` inside `application.ex`.
      if filename.ends_with?(".ex") || filename.ends_with?(".exs")
        return file_contents.includes?("Bandit.PhoenixAdapter") ||
          file_contents.includes?("{Bandit,") ||
          file_contents.includes?("{ Bandit,") ||
          file_contents.includes?("Bandit.start_link") ||
          file_contents.includes?("plug: Bandit")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ex") || filename.ends_with?(".exs") || File.basename(filename) == "mix.exs"
    end

    def set_name
      @name = "elixir_bandit"
    end
  end
end
