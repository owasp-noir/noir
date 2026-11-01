import Vapor

func routes(_ app: Application) throws {
    // 1. Raw string holding fake route - must NOT be detected as an endpoint
    let rawRoute = #"app.get("fake_raw")"#

    // 2. Multiline string holding fake route and braces
    let multiline = """
    {
        app.get("fake_multiline")
    }
    """

    // 3. Nested comments with fake route and braces
    /*
       /*
          app.get("fake_nested")
       */
       {
    */

    // 4. Real route with hostile raw multiline string holding """ and } before param read
    app.get("users", ":id") { req -> String in
        let id = req.parameters.get("id") ?? ""
        let doc = #"""
        Triple quote """ inside raw multiline
        }
        """#
        let q = req.query["q"]
        return "\(id) \(q ?? "")"
    }

    // 5. Real route with string literal holding } before handler auth
    app.post("custom", "auth") { req -> String in
        let template = "closing brace } here"
        req.auth.require(User.self)
        return template
    }
}
