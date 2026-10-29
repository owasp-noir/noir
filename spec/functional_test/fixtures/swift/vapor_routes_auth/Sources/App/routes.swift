import Vapor

func previous(_ app: Application) throws {
    let outside = app.grouped(UserBearerAuthenticator())
    outside.get("previous-only", use: Previous.show)
}

func routes(_ app: Application) throws {
    // Grouped only in `previous`. The guard must not cross the function.
    outside.get("not-in-this-function", use: Missing.show)

    app.group("api") {
        $0.get("packages", ":owner", ":repository", use: PackageController.get)
    }

    app.on(
        .POST,
        "notify-inbound-email",
        body: .collect(maxSize: nil),
        use: MessageController.publicEmail
    )

    app.get(SiteURL.faq.pathComponents, use: FaqController.show)
    app.post(SiteURL.validate.pathComponents, use: ValidateController.validate)
    app.get(":owner", ":repo", ":ref", .fragment(.faviconIco), use: DocController.favicon)
    app.get(":owner", ":repo", ":ref", .fragment(.logoPng), use: DocController.logo)

    app.group(User.APITierAuthenticator(tier: .tier1), User.guardMiddleware()) { protected in
        protected.get("search", use: SearchController.get)
    }

    let tokenProtected = app.grouped(UserToken.authenticator())
    tokenProtected.get("me", use: UserController.me)

    let bearer = app.grouped(UserBearerAuthenticator())
    bearer.get("profile", use: UserController.profile)
    // pad so /channels sits more than 20 lines under the bearer group
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    // pad
    bearer.get("channels", use: ChannelController.index)
}
