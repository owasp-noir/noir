require "../../../models/detector"

module Detector::Erlang
  class Cowboy < Detector
    # Elixir projects pull Cowboy in through `plug_cowboy`, but their
    # routes live in Phoenix/Plug routers that the Elixir analyzers
    # already own. Restricting the manifest check to Erlang's own build
    # files keeps `mix.exs` from lighting this up.
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "rebar.config" || filename.ends_with?(".app.src") || base == "erlang.mk"
        return true if file_contents.matches?(/(?:^|[\s,{"])cowboy(?:_[a-z]+)?(?=$|[\s,}"])/)
      end

      return false unless filename.ends_with?(".erl") || filename.ends_with?(".hrl")

      return true if file_contents.includes?("cowboy_router:compile")
      return true if file_contents.includes?("cowboy:start_clear") || file_contents.includes?("cowboy:start_tls")
      return true if file_contents.matches?(/-(?:behaviour|behavior)\s*\(\s*cowboy_(?:handler|rest|loop|websocket)\s*\)/)
      return true if file_contents.includes?("cowboy_req:")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".erl") || filename.ends_with?(".hrl") ||
        filename.ends_with?(".app.src") ||
        File.basename(filename) == "rebar.config" ||
        File.basename(filename) == "erlang.mk"
    end

    def set_name
      @name = "erlang_cowboy"
    end
  end
end
