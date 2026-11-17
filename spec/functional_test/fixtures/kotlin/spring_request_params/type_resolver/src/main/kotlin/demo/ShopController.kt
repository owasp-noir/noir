package demo

import org.springframework.core.MethodParameter
import org.springframework.web.bind.annotation.*
import org.springframework.web.context.request.NativeWebRequest
import org.springframework.web.method.support.HandlerMethodArgumentResolver

class ShopSession {
    var shopId: Long? = null
    var shopName: String? = null
}

class Ledger {
    var ledgerCode: String? = null
}

class ShopFilter {
    var region: String? = null
}

class ShopSessionResolver : HandlerMethodArgumentResolver {
    override fun supportsParameter(parameter: MethodParameter): Boolean =
        ShopSession::class.java.isAssignableFrom(parameter.parameterType)
    override fun resolveArgument(parameter: MethodParameter, mav: Any?, webRequest: NativeWebRequest, factory: Any?): Any? =
        if (parameter.parameterType == Long::class.java) 0L else ShopSession()
}

class LedgerResolver : HandlerMethodArgumentResolver {
    override fun supportsParameter(parameter: MethodParameter): Boolean {
        return parameter.parameterType == Ledger::class.java
    }
    override fun resolveArgument(parameter: MethodParameter, mav: Any?, webRequest: NativeWebRequest, factory: Any?): Any? = Ledger()
}

@RestController
@RequestMapping("/stores")
class ShopController {
    @GetMapping("/{storeId}/widgets")
    fun widgets(@PathVariable storeId: Long, session: ShopSession?, ledger: Ledger, filter: ShopFilter, limit: Long): String = "ok"
}
