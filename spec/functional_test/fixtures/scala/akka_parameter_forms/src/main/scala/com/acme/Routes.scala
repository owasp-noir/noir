package com.acme

import akka.http.scaladsl.server.Directives._
import akka.http.scaladsl.server.Route
import akka.http.scaladsl.model.headers.HttpCookie

object Routes {
  val route: Route = concat(
    path("p1-defaults") {
      get {
        parameters("color", "backgroundColor".withDefault("white"), "count".as[Int], "debug".optional) { (c, bg, n, d) =>
          complete("x")
        }
      }
    },
    path("p2-single-typed") {
      get {
        parameter("count".as[Int]) { n => complete("x") }
      }
    },
    path("p3-single-optional") {
      get {
        parameter("cursor".optional) { c => complete("x") }
      }
    },
    path("p4-two-directives") {
      get {
        parameters("a", "b") { (a, b) =>
          parameters("c", "d") { (c, d) => complete("x") }
        }
      }
    },
    path("p5-cookie") {
      get {
        cookie("session") { s =>
          optionalCookie("theme") { t =>
            setCookie(HttpCookie("issued", value = "v")) { complete("x") }
          }
        }
      }
    },
    path("p6-control") {
      get {
        parameters("x", "y".optional) { (x, y) => complete("x") }
      }
    }
  )
}
