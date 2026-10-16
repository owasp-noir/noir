package com.example.sourcesets

import zio.http._

object ZioApp {
  val routes = Routes(
    Method.GET / "zio-live" -> handler(Response.text("ok"))
  )
}
