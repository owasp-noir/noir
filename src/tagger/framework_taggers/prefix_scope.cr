# Segment-aware URL-prefix containment, shared by every framework tagger that
# resolves a scoped middleware registration ("this guard covers prefix P — does
# it cover endpoint U?").
#
# The naive `url.starts_with?(prefix)` is wrong in the direction that matters
# most for a security tool: `/admin` then "guards" `/administration/report`,
# and a reviewer skips an endpoint that nothing protects. Compare on a path
# segment boundary instead.
#
# This lived on `GoRouteGroupScope`, where the Go taggers had it right and the
# Express/Ktor ones each carried their own `starts_with?`. It is a property of
# URLs, not of Go, so it belongs somewhere all three can reach.
module PrefixScope
  extend self

  # True when `prefix` guards `url` on a segment boundary, so `/web` covers
  # `/web` and `/web/x` but not `/website`. The root prefix `/` covers every
  # endpoint.
  def prefix_covers?(prefix : String, url : String) : Bool
    return true if prefix == "/"
    url == prefix || url.starts_with?("#{prefix}/")
  end
end
