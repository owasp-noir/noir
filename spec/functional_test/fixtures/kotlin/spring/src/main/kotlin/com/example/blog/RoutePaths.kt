package com.example.blog

// Path constants built from other constants, consumed from another file
// (ConstPathControllers.kt) and from this one.
object RoutePaths {
    const val BASE = "/paths"
    const val TEMPLATE = "$BASE/template"
    const val CONCAT = BASE + "/concat"
    const val BRACED = "${BASE}/braced"
}

const val LOCAL_BASE = "/local"
