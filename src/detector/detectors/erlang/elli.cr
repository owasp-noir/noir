require "../../../models/detector"

module Detector::Erlang
  class Elli < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "rebar.config" || filename.ends_with?(".app.src") || base == "erlang.mk"
        return true if file_contents.matches?(/(?:^|[\s,{"])elli(?:_[a-z]+)?(?=$|[\s,}"])/)
      end

      return false unless filename.ends_with?(".erl") || filename.ends_with?(".hrl")

      return true if file_contents.matches?(/-behaviou?r\s*\(\s*elli_handler\s*\)/)
      return true if file_contents.includes?("elli_request:")
      return true if file_contents.includes?("elli:start_link")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".erl") || filename.ends_with?(".hrl") ||
        filename.ends_with?(".app.src") ||
        File.basename(filename) == "rebar.config" ||
        File.basename(filename) == "erlang.mk"
    end

    def set_name
      @name = "erlang_elli"
    end
  end
end
