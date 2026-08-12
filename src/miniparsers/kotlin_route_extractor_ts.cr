# Tree-sitter-backed Kotlin route extractor, split by concern.
# Spring annotation walking lives in core; each sibling part reopens
# Noir::TreeSitterKotlinRouteExtractor with one concern (STOMP,
# GraphQL, Spring Cloud Gateway, WebFlux functional DSL, shared
# decoding helpers). Requiring this file pulls in the whole extractor,
# exactly as before the split.
require "../utils/url_path"
require "./kotlin_route_extractor_ts/core"
require "./kotlin_route_extractor_ts/gateway"
require "./kotlin_route_extractor_ts/graphql"
require "./kotlin_route_extractor_ts/helpers"
require "./kotlin_route_extractor_ts/stomp"
require "./kotlin_route_extractor_ts/webflux"
