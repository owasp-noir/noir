package com.example

import org.springframework.web.bind.annotation.*

@RestController
class GateController {
    @RequestMapping(value = ["/gate/reset"], method = [RequestMethod.GET])
    fun plain(): String = "plain"

    @RequestMapping(value = ["/gate/reset"], method = [RequestMethod.GET], params = ["ticket"])
    fun t(@RequestParam("ticket") t: String): String = t

    @RequestMapping(value = ["/gate/reset"], method = [RequestMethod.GET], params = ["relink"])
    fun r(@RequestParam("relink") r: String): String = r
}
