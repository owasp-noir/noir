package com.example

import akka.http.scaladsl.server.Directives._

object SecureRoutes {
  val route =
    authenticateBasic(realm = "secure", authenticator) { user =>
      path("api" / "secure") {
        get {
          complete("Secure content")
        }
      }
    }
}

object OAuthRoutes {
  val route =
    authenticateOAuth2(realm = "oauth", oauthAuthenticator) { token =>
      path("api" / "oauth-resource") {
        get {
          complete("OAuth resource")
        }
      }
    }
}

object AdminRoutes {
  val route =
    authorize(hasAdminRole) {
      path("api" / "admin" / "settings") {
        get {
          complete("Admin settings")
        }
      }
    }
}

object HealthRoutes {
  // No auth directives anywhere in this object
  val healthRoute =
    pathPrefix("public") {
      path("health") {
        get {
          complete("ok")
        }
      }
    }
}
