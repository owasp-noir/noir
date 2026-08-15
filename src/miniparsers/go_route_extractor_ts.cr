# Tree-sitter-backed Go route extractor, split by framework family.
# The shared route/group model and the generic router-chain walker
# (gin/echo/fiber/hertz/iris-style APIs) live in core; each sibling
# part reopens Noir::TreeSitterGoRouteExtractor with one framework
# family's decoders. Requiring this file pulls in the whole extractor,
# exactly as before the split.
require "../utils/http_symbols"
require "../utils/text_file"
require "./go_callee_extractor"
require "./go_route_extractor_ts/core"
require "./go_route_extractor_ts/beego"
require "./go_route_extractor_ts/chi"
require "./go_route_extractor_ts/gf"
require "./go_route_extractor_ts/gozero"
require "./go_route_extractor_ts/net_http"
require "./go_route_extractor_ts/restful"
require "./go_route_extractor_ts/statics"
