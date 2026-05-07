module Program

open Giraffe

let webApp =
    choose [
        route "/" >=> text "home"
        GET >=> route "/users" >=> json users
        POST >=> route "/login" >=> handleLogin
        PUT >=> route "/profile" >=> handleProfile
        DELETE >=> route "/items" >=> handleDelete
        PATCH >=> route "/notes" >=> handleNote
        // Typed routef parameters cover both single and multi-token forms.
        routef "/users/%i" handleUser
        routef "/items/%i/notes/%s" handleItemNote
        routef "/big/%d" handleBig
        routef "/flag/%b" handleFlag
        // Mounted sub-routes — both literal and typed prefixes, with
        // nested `subRoute` for prefix concatenation.
        subRoute "/api"
            (choose [
                GET >=> route "/health" >=> text "ok"
                GET >=> route "/version" >=> text "1.0"
                subRoute "/v2"
                    (choose [
                        POST >=> route "/echo" >=> handleEcho
                    ])
            ])
        subRoutef "/users/%i"
            (fun userId ->
                choose [
                    GET >=> route "/profile" >=> handleProfile
                ])
        // Method filter declared on a preceding line, joined to the
        // route via leading `>=>`.
        GET
            >=> route "/multiline"
            >=> handleMultiline
        // routex (regex) and routeCi (case-insensitive).
        GET >=> routex "/foo(/?)" >=> handleFoo
        routeCi "/case" >=> text "case-insensitive"
    ]
