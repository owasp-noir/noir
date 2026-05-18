// Regression guard: F#/Giraffe test sources live under `tests/` or
// have a `*Tests.fs` filename. Routes registered there exercise the
// HttpHandler combinators but never serve real traffic. None of the
// URLs below should appear in the fixture's expected-endpoints list.
module Giraffe.Tests.RoutingTests

open Giraffe

let testApp : HttpHandler =
    choose [
        route "/should-not-appear-test" >=> text "ok"
        route "/should-not-appear-test2" >=> text "ok"
    ]
