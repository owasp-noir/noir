package com.example

import com.linecorp.armeria.server.annotation.Default
import com.linecorp.armeria.server.annotation.Header
import com.linecorp.armeria.server.annotation.Param
import com.linecorp.armeria.server.annotation.PathPrefix
import com.linecorp.armeria.server.annotation.Put
import com.linecorp.armeria.server.annotation.RequestObject

data class UserUpdate(val name: String, val email: String)

@PathPrefix("/users")
class UserController {
    @Put("/{userId}")
    fun update(
        @Param("userId") userId: String,
        @Header("X-Request-Id") requestId: String,
        @Param("dryRun") @Default("false") dryRun: Boolean,
        @RequestObject body: UserUpdate,
    ): String = userId

    // Not an Armeria route: no verb annotation.
    fun helper(): String = "x"
}
