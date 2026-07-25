require "../../../models/detector"

module Detector::Erlang
  class Elli < Detector
    detector_for "erlang_elli",
      extensions: %w[.erl .hrl .app.src],
      basenames: %w[rebar.config erlang.mk]

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "rebar.config" || filename.ends_with?(".app.src") || base == "erlang.mk"
        return true if content_matches?(file_contents, /(?:^|[\s,{"])elli(?:_[a-z]+)?(?=$|[\s,}"])/)
      end

      return false unless filename.ends_with?(".erl") || filename.ends_with?(".hrl")

      return true if content_matches?(file_contents, /-(?:behaviour|behavior)\s*\(\s*elli_handler\s*\)/)
      return true if file_contents.includes?("elli_request:")
      return true if file_contents.includes?("elli:start_link")

      false
    end
  end
end
