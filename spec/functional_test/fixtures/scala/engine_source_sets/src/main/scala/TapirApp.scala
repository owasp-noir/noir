package com.example.sourcesets

import sttp.tapir._

object TapirApp {
  val live = endpoint.get.in("tapir-live").out(stringBody)
}
