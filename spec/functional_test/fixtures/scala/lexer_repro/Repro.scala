package com.example.akka

import akka.http.scaladsl.server.Directives._

object Repro {
  // A triple-quoted doc string whose body looks like routing DSL. The
  // per-line scanner used to treat lines 9-11 as code and surface them.
  val doc =
    """
      path("ghost-from-triple") {
        get { complete("nope") }
      }
    """

  /*
   * path("ghost-from-comment") {
   *   get { complete("nope") }
   * }
   */

  val route =
    path("real") {
      get {
        complete("ok")
      }
    }
}
