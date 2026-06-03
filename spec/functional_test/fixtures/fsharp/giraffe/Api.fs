module Api

open Giraffe

// Route paths declared as string constants and referenced by name.
// `profile` is intentionally unused — unused bindings must not emit
// phantom endpoints.
module Urls =
    let home    = "/home"
    let profile = "/profile"

let apiApp =
    choose [
        // `VERB >=> choose [...]` — the canonical idiom where a verb
        // applies to a whole block. Multi-line layout with the verb on
        // its own line. Every nested route inherits GET.
        GET >=>
            choose [
                route "/products" >=> listProducts
                route Urls.home    >=> showHome
                routef "/products/%i" showProduct
                routeCif "/search/%s" searchHandler
                routeCix "/legacy(/?)" legacyHandler
            ]
        // Inline single-line `VERB >=> choose [...]` form.
        POST >=> choose [
            route "/products" >=> createProduct
            routeBind<Customer> "/customers/{customerId}/orders/{orderId}" handleOrder
        ]
    ]
