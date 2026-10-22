package com.acme.zoo.web

object Hdr {
    object Inner {
        const val DEEP = "x-inner"
    }
    const val LANG = "x-widget-lang"
}

object RoutePaths {
    object V1 {
        const val X = "/x"
    }
    const val AFTER = "/after-nested"
}

object OnePaths { const val A = "/one-a"; const val B = "/one-b" }

object Wire { object Deep { const val DEEP_H = "x-deep-one" }; const val TOP_H = "x-top-one" }
