package ex

import com.linecorp.armeria.server.Server
import com.linecorp.armeria.server.auth.AuthService

fun main() {
    Server.builder()
        .annotatedService()
        .pathPrefix("/kt/admin")
        .decorator(AuthService.newDecorator(authorizer))
        .build(AdminService())
        .serviceUnder("/kt/docs", DocService())
        .service("/kt/public", PublicService())
        .build()
}
