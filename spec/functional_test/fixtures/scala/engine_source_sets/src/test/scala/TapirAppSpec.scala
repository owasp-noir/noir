package com.example.sourcesets

import sttp.tapir._

// Test-only endpoint: nothing serves it.
object TapirAppSpec {
  val testOnly = endpoint.get.in("tapir-test-only").out(stringBody)
}
