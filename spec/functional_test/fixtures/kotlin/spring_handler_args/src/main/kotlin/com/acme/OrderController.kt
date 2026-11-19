package com.acme

import kotlinx.coroutines.flow.Flow
import org.springframework.http.HttpEntity
import org.springframework.web.bind.annotation.*
import reactor.core.publisher.Flux
import reactor.core.publisher.Mono

data class OrderLine(val sku: String, val quantity: Int)

@RestController
@RequestMapping("/kt/orders")
class OrderController {
    @PostMapping("/bulk-list")
    fun bulkList(@RequestBody lines: List<OrderLine>) = "x"

    @PostMapping("/bulk-array")
    fun bulkArray(@RequestBody lines: Array<OrderLine>) = "x"

    @PostMapping("/mono")
    fun mono(@RequestBody line: Mono<OrderLine>): Mono<String> = Mono.just("x")

    @PostMapping("/flux")
    fun flux(@RequestBody lines: Flux<OrderLine>): Mono<String> = Mono.just("x")

    @PostMapping("/flow")
    suspend fun flow(@RequestBody lines: Flow<OrderLine>) = "x"

    @PostMapping("/entity")
    fun entity(entity: HttpEntity<OrderLine>) = "x"

    // A collection of scalars stays one input.
    @PostMapping("/ids")
    fun ids(@RequestBody ids: List<Long>) = "x"
}
