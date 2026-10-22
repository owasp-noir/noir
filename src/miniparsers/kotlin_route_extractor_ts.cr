# Tree-sitter-backed Kotlin route extractor, split by concern.
# Spring annotation walking lives in core; each sibling part reopens
# Noir::TreeSitterKotlinRouteExtractor with one concern (STOMP,
# GraphQL, Spring Cloud Gateway, WebFlux functional DSL, shared
# decoding helpers, and the Kotlin side of the Java-first JAX-RS,
# Micronaut and Javalin walkers). Requiring this file pulls in the
# whole extractor, exactly as before the split.
require "../utils/url_path"
require "./jaxrs_extractor_ts"
require "./micronaut_extractor_ts"
require "./jvm_lambda_dsl_extractor_ts"
require "./kotlin_parameter_extractor_ts"
require "./kotlin_callee_extractor"
require "./kotlin_route_extractor_ts/core"
require "./kotlin_route_extractor_ts/gateway"
require "./kotlin_route_extractor_ts/graphql"
require "./kotlin_route_extractor_ts/helpers"
require "./kotlin_route_extractor_ts/jaxrs"
require "./kotlin_route_extractor_ts/lambda_dsl"
require "./kotlin_route_extractor_ts/micronaut"
require "./kotlin_route_extractor_ts/stomp"
require "./kotlin_route_extractor_ts/webflux"
