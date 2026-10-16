package com.acme.zoo.web.api

import com.acme.zoo.web.Hdr
import com.acme.zoo.web.RoutePaths
import com.acme.zoo.web.dto.FeedRequest
import com.acme.zoo.web.dto.PingReq
import com.acme.zoo.web.dto.SearchFilter
import com.acme.zoo.web.dto.SprocketBatch
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/zoo")
class ZooController {
    @PostMapping("/feed")
    fun feed(@RequestBody req: FeedRequest): String = "ok"

    @RequestMapping("/proxy/**")
    fun proxy(): String = "x"

    @GetMapping("/lang")
    fun lang(@RequestHeader(Hdr.LANG) l: String): String = l

    @GetMapping(RoutePaths.AFTER)
    fun after(@RequestHeader(Hdr.Inner.DEEP) d: String): String = d

    @GetMapping(RoutePaths.V1.X)
    fun nested(): String = "x"

    @PostMapping("/cb")
    fun cb(@RequestHeader(TOKEN_HDR) token: String, @RequestParam(Q_NAME) query: String): String = token

    @GetMapping("/{sid}/hints")
    fun hints(@PathVariable("sid") sid: String, @RequestHeader("x-a") a: String): String = sid

    @PostMapping("/hints")
    fun hints(@RequestHeader("x-a") a: String, @RequestBody batch: SprocketBatch): String = a

    @DeleteMapping("/owners", params = ["ownerKey", "label", "!notThis"])
    fun removeOne(@RequestParam("ownerKey") ownerKey: String, @RequestParam("label") label: String): String = ownerKey

    @PostMapping("/ids")
    fun ids(@RequestBody ids: List<Long>): String = "ok"

    @PutMapping("/blob")
    fun blob(@RequestBody data: ByteArray?): String = "ok"

    @GetMapping("/search")
    fun search(filter: SearchFilter): String = "ok"

    @PostMapping("/ping")
    fun ping(@RequestBody req: PingReq): String = req.who

    companion object {
        const val TOKEN_HDR = "X-Widget-Token"
        const val Q_NAME = "q"
    }
}
