module Program

open Giraffe

// Offset-preserving comments should not move callee line numbers.
(*
   Ignored.beforeRoute()
*)

let webApp =
    choose [
        GET >=> route "/" >=> text "home"
        POST >=> route "/login" >=> handleLogin
        routef "/users/%i" handleUser
        GET
            >=> route "/profile"
            >=> fun next ctx ->
                task {
                    let! user = UserService.load ctx
                    AuditLog.write "profile" user
                    // Ignored.comment()
                    let ignored = "Ignored.string()"
                    return! json (serializeUser user) next ctx
                }
        subRoute "/api"
            (choose [
                PUT >=> route "/items" >=> ItemController.update
            ])
        PATCH >=> route "/pipeline" >=> fun next ctx ->
            let names = [
                "alpha"
                "beta"
            ]
            let response = loadPipeline ctx |> enrich |> renderPipeline
            json response next ctx
    ]

// A `VERB >=> choose [...]` block whose nested route uses a path
// constant. Callee extraction must still find the handler after the
// resolved identifier path.
module Urls =
    let dashboard = "/dashboard"

let adminApp =
    GET >=> choose [
        route Urls.dashboard >=> AdminController.render
    ]
