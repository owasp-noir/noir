package demo

import org.springframework.core.MethodParameter
import org.springframework.web.bind.annotation.*
import org.springframework.web.method.support.HandlerMethodArgumentResolver
import org.springframework.web.context.request.NativeWebRequest

@Target(AnnotationTarget.VALUE_PARAMETER)
@Retention(AnnotationRetention.RUNTIME)
annotation class CurrentAccount

class CurrentAccountResolver : HandlerMethodArgumentResolver {
    override fun supportsParameter(parameter: MethodParameter) =
        parameter.hasParameterAnnotation(CurrentAccount::class.java)
    override fun resolveArgument(parameter: MethodParameter, mav: Any?, webRequest: NativeWebRequest, factory: Any?): Any? =
        webRequest.getAttribute("accountId", NativeWebRequest.SCOPE_REQUEST)
}

data class PostRequest(val title: String)

@RestController
@RequestMapping("/posts")
class PostController {
    @PostMapping
    fun create(@CurrentAccount accountId: Long, @RequestBody req: PostRequest): String = "ok"

    @GetMapping("/{postId}")
    fun detail(@PathVariable postId: String, @CurrentAccount accountId: Long): String = "ok"
}
